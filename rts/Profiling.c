/* -----------------------------------------------------------------------------
 *
 * (c) The GHC Team, 1998-2000
 *
 * Support for profiling
 *
 * ---------------------------------------------------------------------------*/

#if defined(PROFILING)

#include "rts/PosixSource.h"
#include "Rts.h"

#include "RtsUtils.h"
#include "Profiling.h"
#include "Proftimer.h"
#include "ProfHeap.h"
#include "Arena.h"
#include "RetainerProfile.h"
#include "ProfilerReport.h"
#include "ProfilerReportJson.h"
#include "Printer.h"
#include "Capability.h"

#include <fs_rts.h>
#include <string.h>

#if defined(DEBUG) || defined(PROFILING)
#include "Trace.h"
#endif

/*
 * Profiling allocation arena.
 */
#if defined(DEBUG)
Arena *prof_arena;
#else
static Arena *prof_arena;
#endif

/*
 * Global variables used to assign unique IDs to cc's, ccs's, and
 * closure_cats
 */

static unsigned int CC_ID  = 1;
static unsigned int CCS_ID = 1;

/* Globals for opening the profiling log file(s)
 */
static char *prof_filename; /* prof report file name = <program>.prof */
FILE *prof_file;

// List of all cost centres. Used for reporting.
CostCentre      *CC_LIST  = NULL;
// All cost centre stacks temporarily appear here, to be able to make CCS_MAIN a
// parent of all cost centres stacks (done in refreshProfilingCCSs()).
static CostCentreStack *CCS_LIST = NULL;

#if defined(THREADED_RTS)
Mutex ccs_mutex;
#endif

/*
 * Built-in cost centres and cost-centre stacks:
 *
 *    MAIN   is the root of the cost-centre stack tree.  If there are
 *           no {-# SCC #-}s in the program, all costs will be attributed
 *           to MAIN.
 *
 *    SYSTEM is the RTS in general (scheduler, etc.).  All costs for
 *           RTS operations apart from garbage collection are attributed
 *           to SYSTEM.
 *
 *    GC     is the storage manager / garbage collector.
 *
 *    OVERHEAD gets all costs generated by the profiling system
 *           itself.  These are costs that would not be incurred
 *           during non-profiled execution of the program.
 *
 *    DONT_CARE is a placeholder cost-centre we assign to static
 *           constructors.  It should *never* accumulate any costs.
 *
 *    PINNED accumulates memory allocated to pinned objects, which
 *           cannot be profiled separately because we cannot reliably
 *           traverse pinned memory.
 */

CC_DECLARE(CC_MAIN,      "MAIN",        "MAIN",      "<built-in>", CC_NOT_CAF, );
CC_DECLARE(CC_SYSTEM,    "SYSTEM",      "SYSTEM",    "<built-in>", CC_NOT_CAF, );
CC_DECLARE(CC_GC,        "GC",          "GC",        "<built-in>", CC_NOT_CAF, );
CC_DECLARE(CC_OVERHEAD,  "OVERHEAD_of", "PROFILING", "<built-in>", CC_NOT_CAF, );
CC_DECLARE(CC_DONT_CARE, "DONT_CARE",   "MAIN",      "<built-in>", CC_NOT_CAF, );
CC_DECLARE(CC_PINNED,    "PINNED",      "SYSTEM",    "<built-in>", CC_NOT_CAF, );
CC_DECLARE(CC_IDLE,      "IDLE",        "IDLE",      "<built-in>", CC_NOT_CAF, );

CCS_DECLARE(CCS_MAIN,       CC_MAIN,       );
CCS_DECLARE(CCS_SYSTEM,     CC_SYSTEM,     );
CCS_DECLARE(CCS_GC,         CC_GC,         );
CCS_DECLARE(CCS_OVERHEAD,   CC_OVERHEAD,   );
CCS_DECLARE(CCS_DONT_CARE,  CC_DONT_CARE,  );
CCS_DECLARE(CCS_PINNED,     CC_PINNED,     );
CCS_DECLARE(CCS_IDLE,       CC_IDLE,       );

/*
 * Static Functions
 */

static  CostCentreStack * appendCCS       ( CostCentreStack *ccs1,
                                            CostCentreStack *ccs2 );
static  CostCentreStack * actualPush_     ( CostCentreStack *ccs, CostCentre *cc,
                                            CostCentreStack *new_ccs );
static  void              inheritCosts    ( CostCentreStack *ccs );
static  ProfilerTotals    countTickss     ( CostCentreStack const *ccs );
static  CostCentreStack * checkLoop       ( CostCentreStack *ccs,
                                            CostCentre *cc );
static  void              sortCCSTree     ( CostCentreStack *ccs );
static  CostCentreStack * pruneCCSTree    ( CostCentreStack *ccs );
static  CostCentreStack * actualPush      ( CostCentreStack *, CostCentre * );
static  CostCentreStack * isInIndexTable  ( IndexTable *, CostCentre * );
static  IndexTable *      addToIndexTable ( IndexTable *, CostCentreStack *,
                                            CostCentre *, bool );
static  void              ccsSetSelected  ( CostCentreStack *ccs );
static  void              aggregateCCCosts( CostCentreStack *ccs );
static  void              registerCC      ( CostCentre *cc );
static  void              registerCCS     ( CostCentreStack *ccs );

static  void              initTimeProfiling    ( void );
static  void              initProfilingLogFile ( void );

/* -----------------------------------------------------------------------------
   Initialise the profiling environment
   -------------------------------------------------------------------------- */

static void
dumpCostCentresToEventLog(void)
{
#if defined(PROFILING)
    CostCentre *cc, *next;
    for (cc = CC_LIST; cc != NULL; cc = next) {
        next = cc->link;
        traceHeapProfCostCentre(cc->ccID, cc->label, cc->module,
                                cc->srcloc, cc->is_caf);
    }
#endif
}

void initProfiling (void)
{
    // initialise our arena
    prof_arena = newArena();

    /* for the benefit of allocate()... */
    {
        uint32_t n;
        for (n=0; n < getNumCapabilities(); n++) {
            getCapability(n)->r.rCCCS = CCS_SYSTEM;
        }
    }

#if defined(THREADED_RTS)
    initMutex(&ccs_mutex);
#endif

    /* Set up the log file, and dump the header and cost centre
     * information into it.
     */
    initProfilingLogFile();

    /* Register all the cost centres / stacks in the program
     * CC_MAIN gets link = 0, all others have non-zero link.
     */
    registerCC(CC_MAIN);
    registerCC(CC_SYSTEM);
    registerCC(CC_GC);
    registerCC(CC_OVERHEAD);
    registerCC(CC_DONT_CARE);
    registerCC(CC_PINNED);
    registerCC(CC_IDLE);

    registerCCS(CCS_SYSTEM);
    registerCCS(CCS_GC);
    registerCCS(CCS_OVERHEAD);
    registerCCS(CCS_DONT_CARE);
    registerCCS(CCS_PINNED);
    registerCCS(CCS_IDLE);
    registerCCS(CCS_MAIN);

    /* find all the registered cost centre stacks, and make them
     * children of CCS_MAIN.
     */
    ASSERT(CCS_LIST == CCS_MAIN);
    CCS_LIST = CCS_LIST->prevStack;
    CCS_MAIN->prevStack = NULL;
    CCS_MAIN->root = CCS_MAIN;
    ccsSetSelected(CCS_MAIN);

    refreshProfilingCCSs();

    if (RtsFlags.CcFlags.doCostCentres) {
        initTimeProfiling();
    }

    traceInitEvent(dumpCostCentresToEventLog);
}



//
// Should be called after loading any new Haskell code.
//
void refreshProfilingCCSs (void)
{
    // make CCS_MAIN the parent of all the pre-defined CCSs.
    CostCentreStack *next;
    for (CostCentreStack *ccs = CCS_LIST; ccs != NULL; ) {
        next = ccs->prevStack;
        ccs->prevStack = NULL;
        actualPush_(CCS_MAIN,ccs->cc,ccs);
        ccs->root = ccs;
        ccs = next;
    }
    CCS_LIST = NULL;
}

void
freeProfiling (void)
{
    arenaFree(prof_arena);
}

CostCentre *mkCostCentre (char *label, char *module, char *srcloc)
{
    CostCentre *cc = stgMallocBytes (sizeof(CostCentre), "mkCostCentre");
    cc->label = label;
    cc->module = module;
    cc->srcloc = srcloc;
    cc->is_caf = 0;
    cc->mem_alloc = 0;
    cc->time_ticks = 0;
    cc->link = NULL;
    return cc;
}

static void
initProfilingLogFile(void)
{
    // Figure out output file name stem.
    char const *stem;
    if (RtsFlags.CcFlags.outputFileNameStem) {
        stem = RtsFlags.CcFlags.outputFileNameStem;
    } else {
        char *prog;

        prog = arenaAlloc(prof_arena, strlen(prog_name) + 1);
        strcpy(prog, prog_name);
#if defined(mingw32_HOST_OS)
        // on Windows, drop the .exe suffix if there is one
        {
            char *suff;
            suff = strrchr(prog,'.');
            if (suff != NULL && !strcmp(suff,".exe")) {
                *suff = '\0';
            }
        }
#endif
        stem = prog;
    }

    if (RtsFlags.CcFlags.doCostCentres == 0 && !doingRetainerProfiling())
    {
        /* No need for the <stem>.prof file */
        prof_filename = NULL;
        prof_file = NULL;
    }
    else
    {
        /* Initialise the log file name */
        prof_filename = arenaAlloc(prof_arena, strlen(stem) + 6);
        sprintf(prof_filename, "%s.prof", stem);

        /* open the log file */
        if ((prof_file = __rts_fopen(prof_filename, "w+")) == NULL) {
            debugBelch("Can't open profiling report file %s\n", prof_filename);
            RtsFlags.CcFlags.doCostCentres = 0;
            // Retainer profiling (`-hr` or `-hr<cc> -h<x>`) writes to
            // both <program>.hp as <program>.prof.
            if (doingRetainerProfiling()) {
                RtsFlags.ProfFlags.doHeapProfile = 0;
            }
        }
    }
}

void
initTimeProfiling(void)
{
    traceProfBegin();
    /* Start ticking */
    startProfTimer();
};

void
endProfiling ( void )
{
    if (RtsFlags.CcFlags.doCostCentres) {
        stopProfTimer();
    }
}

/* -----------------------------------------------------------------------------
   Registering CCs and CCSs

   Registering a CC or CCS consists of
     - assigning it a unique ID
     - linking it onto the list of registered CCs/CCSs

   Cost centres are registered at startup by a C constructor function
   generated by the compiler (ProfInit.hs) in the _stub.c file for each module.
 -------------------------------------------------------------------------- */

static void
registerCC(CostCentre *cc)
{
    if (cc->link == NULL) {
        cc->link = CC_LIST;
        CC_LIST = cc;
        cc->ccID = CC_ID++;
    }
}

static void registerCCS(CostCentreStack *ccs)
{
    if (ccs->prevStack == NULL) {
        ccs->prevStack = CCS_LIST;
        CCS_LIST = ccs;
        ccs->ccsID = CCS_ID++;
    }
}

void registerCcList(CostCentre **cc_list)
{
    for (CostCentre **i = cc_list; *i != NULL; i++) {
        registerCC(*i);
    }
}

void registerCcsList(CostCentreStack **cc_list)
{
    for (CostCentreStack **i = cc_list; *i != NULL; i++) {
        registerCCS(*i);
    }
}

/* -----------------------------------------------------------------------------
   Set CCCS when entering a function.

   The algorithm is as follows.

     ccs ++> ccsfn  =  ccs ++ dropCommonPrefix ccs ccsfn

   where

     dropCommonPrefix A B
        -- returns the suffix of B after removing any prefix common
        -- to both A and B.

   e.g.

     <a,b,c> ++> <>      = <a,b,c>
     <a,b,c> ++> <d>     = <a,b,c,d>
     <a,b,c> ++> <a,b>   = <a,b,c>
     <a,b>   ++> <a,b,c> = <a,b,c>
     <a,b,c> ++> <a,b,d> = <a,b,c,d>

   -------------------------------------------------------------------------- */

// implements  c1 ++> c2,  where c1 and c2 are equal depth
//
static CostCentreStack *
enterFunEqualStacks (CostCentreStack *ccs0,
                     CostCentreStack *ccsapp,
                     CostCentreStack *ccsfn)
{
    ASSERT(ccsapp->depth == ccsfn->depth);
    if (ccsapp == ccsfn) return ccs0;
    return pushCostCentre(enterFunEqualStacks(ccs0,
                                              ccsapp->prevStack,
                                              ccsfn->prevStack),
                          ccsfn->cc);
}

// implements  c1 ++> c2,  where c2 is deeper than c1.
// Drop elements of c2 until we have equal stacks, call
// enterFunEqualStacks(), and then push on the elements that we
// dropped in reverse order.
//
static CostCentreStack *
enterFunCurShorter (CostCentreStack *ccsapp, CostCentreStack *ccsfn, StgWord n)
{
    if (n == 0) {
        ASSERT(ccsfn->depth == ccsapp->depth);
        return enterFunEqualStacks(ccsapp,ccsapp,ccsfn);;
    } else {
        ASSERT(ccsfn->depth > ccsapp->depth);
        return pushCostCentre(enterFunCurShorter(ccsapp, ccsfn->prevStack, n-1),
                              ccsfn->cc);
    }
}

void enterFunCCS (StgRegTable *reg, CostCentreStack *ccsfn)
{
    CostCentreStack *ccsapp;

    // common case 1: both stacks are the same
    if (ccsfn == reg->rCCCS) {
        return;
    }

    // common case 2: the function stack is empty, or just CAF
    if (ccsfn->cc->is_caf) {
        return;
    }

    ccsapp = reg->rCCCS;
    reg->rCCCS = CCS_OVERHEAD;

    // common case 3: the stacks are completely different (e.g. one is a
    // descendent of MAIN and the other of a CAF): we append the whole
    // of the function stack to the current CCS.
    if (ccsfn->root != ccsapp->root) {
        reg->rCCCS = appendCCS(ccsapp,ccsfn);
        return;
    }

    // uncommon case 4: ccsapp is deeper than ccsfn
    if (ccsapp->depth > ccsfn->depth) {
        uint32_t i, n;
        CostCentreStack *tmp = ccsapp;
        n = ccsapp->depth - ccsfn->depth;
        for (i = 0; i < n; i++) {
            tmp = tmp->prevStack;
        }
        reg->rCCCS = enterFunEqualStacks(ccsapp,tmp,ccsfn);
        return;
    }

    // uncommon case 5: ccsfn is deeper than CCCS
    if (ccsfn->depth > ccsapp->depth) {
        reg->rCCCS = enterFunCurShorter(ccsapp, ccsfn,
                                        ccsfn->depth - ccsapp->depth);
        return;
    }

    // uncommon case 6: stacks are equal depth, but different
    reg->rCCCS = enterFunEqualStacks(ccsapp,ccsapp,ccsfn);
}

/* -----------------------------------------------------------------------------
   Decide whether closures with this CCS should contribute to the heap
   profile.
   -------------------------------------------------------------------------- */

static void
ccsSetSelected (CostCentreStack *ccs)
{
    if (RtsFlags.ProfFlags.modSelector) {
        if (! strMatchesSelector (ccs->cc->module,
                                  RtsFlags.ProfFlags.modSelector) ) {
            ccs->selected = 0;
            return;
        }
    }
    if (RtsFlags.ProfFlags.ccSelector) {
        if (! strMatchesSelector (ccs->cc->label,
                                  RtsFlags.ProfFlags.ccSelector) ) {
            ccs->selected = 0;
            return;
        }
    }
    if (RtsFlags.ProfFlags.ccsSelector) {
        CostCentreStack *c;
        for (c = ccs; c != NULL; c = c->prevStack)
        {
            if ( strMatchesSelector (c->cc->label,
                                     RtsFlags.ProfFlags.ccsSelector) ) {
                break;
            }
        }
        if (c == NULL) {
            ccs->selected = 0;
            return;
        }
    }

    ccs->selected = 1;
    return;
}

/* -----------------------------------------------------------------------------
   Cost-centre stack manipulation
   -------------------------------------------------------------------------- */

/* Append ccs1 to ccs2 (ignoring any CAF cost centre at the root of ccs1 */
CostCentreStack *
appendCCS ( CostCentreStack *ccs1, CostCentreStack *ccs2 )
{
    IF_DEBUG(prof,
            if (ccs1 != ccs2) {
              debugBelch("Appending ");
              debugCCS(ccs1);
              debugBelch(" to ");
              debugCCS(ccs2);
              debugBelch("\n");});

    if (ccs1 == ccs2) {
        return ccs1;
    }

    if (ccs2 == CCS_MAIN || ccs2->cc->is_caf) {
        // stop at a CAF element
        return ccs1;
    }

    return pushCostCentre(appendCCS(ccs1, ccs2->prevStack), ccs2->cc);
}

// Pick one:
// #define RECURSION_DROPS
#define RECURSION_TRUNCATES

CostCentreStack *
pushCostCentre (CostCentreStack *ccs, CostCentre *cc)
{
    IF_DEBUG(prof,
             traceBegin("pushing %s on ", cc->label);
             debugCCS(ccs);
             traceEnd(););

    CostCentreStack *ret;

    if (ccs == EMPTY_STACK) {
        ACQUIRE_LOCK(&ccs_mutex);
        ret = actualPush(ccs,cc);
    }
    else
    {
        if (ccs->cc == cc) {
            return ccs;
        } else {
            // check if we've already memoized this stack
            IndexTable *ixtable = ccs->indexTable;
            CostCentreStack *temp_ccs = isInIndexTable(ixtable,cc);

            if (temp_ccs != EMPTY_STACK) {
                return temp_ccs;
            } else {

                // not in the IndexTable, now we take the lock:
                ACQUIRE_LOCK(&ccs_mutex);

                if (ccs->indexTable != ixtable)
                {
                    // someone modified ccs->indexTable while
                    // we did not hold the lock, so we must
                    // check it again:
                    temp_ccs = isInIndexTable(ixtable,cc);
                    if (temp_ccs != EMPTY_STACK)
                    {
                        RELEASE_LOCK(&ccs_mutex);
                        return temp_ccs;
                    }
                }
                temp_ccs = checkLoop(ccs,cc);
                if (temp_ccs != NULL) {
                    // This CC is already in the stack somewhere.
                    // This could be recursion, or just calling
                    // another function with the same CC.
                    // A number of policies are possible at this
                    // point, we implement two here:
                    //   - truncate the stack to the previous instance
                    //     of this CC
                    //   - ignore this push, return the same stack.
                    //
                    CostCentreStack *new_ccs;
#if defined(RECURSION_TRUNCATES)
                    new_ccs = temp_ccs;
#else // defined(RECURSION_DROPS)
                    new_ccs = ccs;
#endif
                    ccs->indexTable = addToIndexTable (ccs->indexTable,
                                                       new_ccs, cc, true);
                    ret = new_ccs;
                } else {
                    ret = actualPush (ccs,cc);
                }
            }
        }
    }

    RELEASE_LOCK(&ccs_mutex);
    return ret;
}

static CostCentreStack *
checkLoop (CostCentreStack *ccs, CostCentre *cc)
{
    while (ccs != EMPTY_STACK) {
        if (ccs->cc == cc)
            return ccs;
        ccs = ccs->prevStack;
    }
    return NULL;
}

static CostCentreStack *
actualPush (CostCentreStack *ccs, CostCentre *cc)
{
    CostCentreStack *new_ccs;

    // allocate space for a new CostCentreStack
    new_ccs = (CostCentreStack *) arenaAlloc(prof_arena, sizeof(CostCentreStack));

    return actualPush_(ccs, cc, new_ccs);
}

static CostCentreStack *
actualPush_ (CostCentreStack *ccs, CostCentre *cc, CostCentreStack *new_ccs)
{
    /* assign values to each member of the structure */
    new_ccs->ccsID = CCS_ID++;
    new_ccs->cc = cc;
    new_ccs->prevStack = ccs;
    new_ccs->root = ccs->root;
    new_ccs->depth = ccs->depth + 1;

    new_ccs->indexTable = EMPTY_TABLE;

    /* Initialise the various _scc_ counters to zero
     */
    new_ccs->scc_count        = 0;

    /* Initialize all other stats here.  There should be a quick way
     * that's easily used elsewhere too
     */
    new_ccs->time_ticks = 0;
    new_ccs->mem_alloc = 0;
    new_ccs->inherited_ticks = 0;
    new_ccs->inherited_alloc = 0;

    // Set the selected field.
    ccsSetSelected(new_ccs);

    /* update the memoization table for the parent stack */
    ccs->indexTable = addToIndexTable(ccs->indexTable, new_ccs, cc,
                                      false/*not a back edge*/);

    /* return a pointer to the new stack */
    return new_ccs;
}


static CostCentreStack *
isInIndexTable(IndexTable *it, CostCentre *cc)
{
    while (it!=EMPTY_TABLE)
    {
        if (it->cc == cc)
            return it->ccs;
        else
            it = it->next;
    }

    /* otherwise we never found it so return EMPTY_TABLE */
    return EMPTY_TABLE;
}


static IndexTable *
addToIndexTable (IndexTable *it, CostCentreStack *new_ccs,
                 CostCentre *cc, bool back_edge)
{
    IndexTable *new_it;

    new_it = arenaAlloc(prof_arena, sizeof(IndexTable));

    new_it->cc = cc;
    new_it->ccs = new_ccs;
    new_it->next = it;
    new_it->back_edge = back_edge;
    return new_it;
}

/* -----------------------------------------------------------------------------
   Generating a time & allocation profiling report.
   -------------------------------------------------------------------------- */

/* We omit certain system-related CCs and CCSs from the default
 * reports, so as not to cause confusion.
 */
bool
ignoreCC (CostCentre const *cc)
{
    return RtsFlags.CcFlags.doCostCentres < COST_CENTRES_ALL &&
        (   cc == CC_OVERHEAD
         || cc == CC_DONT_CARE
         || cc == CC_GC
         || cc == CC_SYSTEM
         || cc == CC_IDLE);
}

bool
ignoreCCS (CostCentreStack const *ccs)
{
    return RtsFlags.CcFlags.doCostCentres < COST_CENTRES_ALL &&
        (   ccs == CCS_OVERHEAD
         || ccs == CCS_DONT_CARE
         || ccs == CCS_GC
         || ccs == CCS_SYSTEM
         || ccs == CCS_IDLE);
}

void
reportCCSProfiling( void )
{
    stopProfTimer();
    if (RtsFlags.CcFlags.doCostCentres == 0) return;

    ProfilerTotals totals = countTickss(CCS_MAIN);
    aggregateCCCosts(CCS_MAIN);
    inheritCosts(CCS_MAIN);
    CostCentreStack *stack = pruneCCSTree(CCS_MAIN);
    sortCCSTree(stack);

    if (RtsFlags.CcFlags.doCostCentres == COST_CENTRES_JSON) {
        writeCCSReportJson(prof_file, stack, totals);
    } else {
        writeCCSReport(prof_file, stack, totals);
    }
}

/* -----------------------------------------------------------------------------
 * Accumulating total allocations and tick count
   -------------------------------------------------------------------------- */

/* Helper */
static void
countTickss_(CostCentreStack const *ccs, ProfilerTotals *totals)
{
    if (!ignoreCCS(ccs)) {
        totals->total_alloc += ccs->mem_alloc;
        totals->total_prof_ticks += ccs->time_ticks;
    }
    for (IndexTable *i = ccs->indexTable; i != NULL; i = i->next) {
        if (!i->back_edge) {
            countTickss_(i->ccs, totals);
        }
    }
}

/* Traverse the cost centre stack tree and accumulate
 * total ticks/allocations.
 */
static ProfilerTotals
countTickss(CostCentreStack const *ccs)
{
    ProfilerTotals totals = {0,0};
    countTickss_(ccs, &totals);
    return totals;
}

/* Traverse the cost centre stack tree and inherit ticks & allocs.
 */
static void
inheritCosts(CostCentreStack *ccs)
{
    IndexTable *i;

    if (ignoreCCS(ccs)) { return; }

    ccs->inherited_ticks += ccs->time_ticks;
    ccs->inherited_alloc += ccs->mem_alloc;

    for (i = ccs->indexTable; i != NULL; i = i->next)
        if (!i->back_edge) {
            inheritCosts(i->ccs);
            ccs->inherited_ticks += i->ccs->inherited_ticks;
            ccs->inherited_alloc += i->ccs->inherited_alloc;
        }

    return;
}

static void
aggregateCCCosts( CostCentreStack *ccs )
{
    IndexTable *i;

    ccs->cc->mem_alloc += ccs->mem_alloc;
    ccs->cc->time_ticks += ccs->time_ticks;

    for (i = ccs->indexTable; i != 0; i = i->next) {
        if (!i->back_edge) {
            aggregateCCCosts(i->ccs);
        }
    }
}

//
// Prune CCSs with zero entries, zero ticks or zero allocation from
// the tree, unless COST_CENTRES_ALL is on.
//
static CostCentreStack *
pruneCCSTree (CostCentreStack *ccs)
{
    CostCentreStack *ccs1;
    IndexTable *i, **prev;

    prev = &ccs->indexTable;
    for (i = ccs->indexTable; i != 0; i = i->next) {
        if (i->back_edge) { continue; }

        ccs1 = pruneCCSTree(i->ccs);
        if (ccs1 == NULL) {
            *prev = i->next;
        } else {
            prev = &(i->next);
        }
    }

    if ( (RtsFlags.CcFlags.doCostCentres >= COST_CENTRES_ALL
          /* force printing of *all* cost centres if -P -P */ )

         || ( ccs->indexTable != 0 )
         || ( ccs->scc_count || ccs->time_ticks || ccs->mem_alloc )
        ) {
        return ccs;
    } else {
        return NULL;
    }
}

static IndexTable*
insertIndexTableInSortedList(IndexTable* tbl, IndexTable* sortedList)
{
    StgWord tbl_ticks = tbl->ccs->scc_count;
    char*   tbl_label = tbl->ccs->cc->label;

    IndexTable *prev   = NULL;
    IndexTable *cursor = sortedList;

    while (cursor != NULL) {
        StgWord cursor_ticks = cursor->ccs->scc_count;
        char*   cursor_label = cursor->ccs->cc->label;

        if (tbl_ticks > cursor_ticks ||
                (tbl_ticks == cursor_ticks && strcmp(tbl_label, cursor_label) < 0)) {
            if (prev == NULL) {
                tbl->next = sortedList;
                return tbl;
            } else {
                prev->next = tbl;
                tbl->next = cursor;
                return sortedList;
            }
        } else {
            prev   = cursor;
            cursor = cursor->next;
        }
    }

    prev->next = tbl;
    return sortedList;
}

static void
sortCCSTree(CostCentreStack *ccs)
{
    if (ccs->indexTable == NULL) return;

    for (IndexTable *tbl = ccs->indexTable; tbl != NULL; tbl = tbl->next)
        if (!tbl->back_edge)
            sortCCSTree(tbl->ccs);

    IndexTable *sortedList    = ccs->indexTable;
    IndexTable *nonSortedList = sortedList->next;
    sortedList->next = NULL;

    while (nonSortedList != NULL)
    {
        IndexTable *nonSortedTail = nonSortedList->next;
        nonSortedList->next = NULL;
        sortedList = insertIndexTableInSortedList(nonSortedList, sortedList);
        nonSortedList = nonSortedTail;
    }

    ccs->indexTable = sortedList;
}

void
fprintCCS( FILE *f, CostCentreStack *ccs )
{
    fprintf(f,"<");
    for (; ccs && ccs != CCS_MAIN; ccs = ccs->prevStack ) {
        fprintf(f,"%s.%s", ccs->cc->module, ccs->cc->label);
        if (ccs->prevStack && ccs->prevStack != CCS_MAIN) {
            fprintf(f,",");
        }
    }
    fprintf(f,">");
}

// Returns: True if the call stack ended with CAF
static bool fprintCallStack (CostCentreStack *ccs)
{
    CostCentreStack *prev;

    fprintf(stderr,"%s.%s", ccs->cc->module, ccs->cc->label);
    prev = ccs->prevStack;
    while (prev && prev != CCS_MAIN) {
        ccs = prev;
        fprintf(stderr, ",\n  called from %s.%s",
                ccs->cc->module, ccs->cc->label);
        prev = ccs->prevStack;
    }
    fprintf(stderr, "\n");

    return (!strncmp(ccs->cc->label, "CAF", 3));
}

/* For calling from .cmm code, where we can't reliably refer to stderr */
void
fprintCCS_stderr (CostCentreStack *ccs, StgClosure *exception, StgTSO *tso)
{
    bool is_caf;
    StgPtr frame;
    StgStack *stack;
    CostCentreStack *prev_ccs;
    uint32_t depth = 0;
    const uint32_t MAX_DEPTH = 10; // don't print gigantic chains of stacks

    {
        const char *desc;
        const StgInfoTable *info;
        info = get_itbl(UNTAG_CONST_CLOSURE(exception));
        switch (info->type) {
        case CONSTR:
        case CONSTR_1_0:
        case CONSTR_0_1:
        case CONSTR_2_0:
        case CONSTR_1_1:
        case CONSTR_0_2:
        case CONSTR_NOCAF:
            desc = GET_CON_DESC(itbl_to_con_itbl(info));
            break;
       default:
            desc = closure_type_names[info->type];
            break;
        }
        fprintf(stderr, "*** Exception (reporting due to +RTS -xc): (%s), stack trace: \n  ", desc);
    }

    is_caf = fprintCallStack(ccs);

    // traverse the stack down to the enclosing update frame to
    // find out where this CCS was evaluated from...

    stack = tso->stackobj;
    frame = stack->sp;
    prev_ccs = ccs;

    for (; is_caf && depth < MAX_DEPTH; depth++)
    {
        switch (get_itbl((StgClosure*)frame)->type)
        {
        case UPDATE_FRAME:
            ccs = ((StgUpdateFrame*)frame)->header.prof.ccs;
            frame += sizeofW(StgUpdateFrame);
            if (ccs == CCS_MAIN) {
                goto done;
            }
            if (ccs == prev_ccs) {
                // ignore if this is the same as the previous stack,
                // we're probably in library code and haven't
                // accumulated any more interesting stack items
                // since the last update frame.
                break;
            }
            prev_ccs = ccs;
            fprintf(stderr, "  --> evaluated by: ");
            is_caf = fprintCallStack(ccs);
            break;
        case UNDERFLOW_FRAME:
            stack = ((StgUnderflowFrame*)frame)->next_chunk;
            frame = stack->sp;
            break;
        case STOP_FRAME:
            goto done;
        default:
            frame += stack_frame_sizeW((StgClosure*)frame);
            break;
        }
    }
done:
    return;
}

#if defined(DEBUG)
void
debugCCS( CostCentreStack *ccs )
{
    debugBelch("<");
    for (; ccs && ccs != CCS_MAIN; ccs = ccs->prevStack ) {
        debugBelch("%s.%s", ccs->cc->module, ccs->cc->label);
        if (ccs->prevStack && ccs->prevStack != CCS_MAIN) {
            debugBelch(",");
        }
    }
    debugBelch(">");
}
#endif /* DEBUG */

#endif /* PROFILING */
