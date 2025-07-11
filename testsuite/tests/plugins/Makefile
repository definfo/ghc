TOP=../..
include $(TOP)/mk/boilerplate.mk
include $(TOP)/mk/test.mk

# Each of the tests also exercise the various ways to bring plugins into scope

# -hide-all-plugin-packages + -plugin-package
.PHONY: plugins01
plugins01:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) --make -v0 plugins01.hs -package-db simple-plugin/pkg.plugins01/local.package.conf -fplugin Simple.Plugin -fplugin-opt Simple.Plugin:Irrelevant_Option -hide-all-plugin-packages -plugin-package simple-plugin
	./plugins01

# -hide-all-packages + -plugin-package
.PHONY: plugins07
plugins07:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) --make -v0 -O plugins07.hs -package-db rule-defining-plugin/pkg.plugins07/local.package.conf -hide-all-packages -package base -plugin-package rule-defining-plugin -fplugin=RuleDefiningPlugin
	./plugins07

.PHONY: plugins08
plugins08:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) --make -v0 plugins08.hs -package-db simple-plugin/pkg.plugins08/local.package.conf
	./plugins08

.PHONY: plugins09
plugins09:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) --make -v0 plugins09.hs -package-db simple-plugin/pkg.plugins09/local.package.conf -fplugin Simple.SourcePlugin -fplugin-opt Simple.SourcePlugin:a -fplugin-opt Simple.SourcePlugin:b -plugin-package simple-plugin

.PHONY: plugins10
plugins10:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) --make -v0 plugins10.hs QuasiQuotation.hs -package-db simple-plugin/pkg.plugins10/local.package.conf -fplugin Simple.SourcePlugin -plugin-package simple-plugin

.PHONY: plugins11
plugins11:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) --make -v0 plugins11.hs -package-db simple-plugin/pkg.plugins11/local.package.conf -plugin-package simple-plugin

.PHONY: plugins12
plugins12:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) --make -v0 plugins12.hs -package-db simple-plugin/pkg.plugins12/local.package.conf -plugin-package simple-plugin

.PHONY: plugins13
plugins13:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) --make -v0 plugins13.hs PluginFilteredExport.hs -package-db simple-plugin/pkg.plugins13/local.package.conf -plugin-package simple-plugin

.PHONY: plugins14
plugins14:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) --make -v0 plugins14.hs -package-db simple-plugin/pkg.plugins14/local.package.conf -plugin-package simple-plugin

.PHONY: plugins15
plugins15:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) --make -v0 plugins15.hs MetaRemoveHelper.hs -package-db simple-plugin/pkg.plugins15/local.package.conf -plugin-package simple-plugin

# -package (should work for backwards compatibility)
.PHONY: T10420
T10420:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) --make -v0 -O T10420.hs -package-db rule-defining-plugin/pkg.T10420/local.package.conf -hide-all-packages -package base -package rule-defining-plugin
	./T10420

.PHONY: T10294
T10294:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) -c -v0 T10294.hs -package-db annotation-plugin/pkg.T10294/local.package.conf -package annotation-plugin -fplugin=SayAnnNames

.PHONY: T10294a
T10294a:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) -c -v0 T10294a.hs -package-db annotation-plugin/pkg.T10294a/local.package.conf -package annotation-plugin -fplugin=SayAnnNames

.PHONY: frontend01
frontend01:
	$(RM) FrontendPlugin.hi FrontendPlugin.o frontend01 frontend01.hi frontend.o
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) -Wall -package ghc -c FrontendPlugin.hs
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) --frontend FrontendPlugin -ffrontend-opt foo -ffrontend-opt bar frontend01
	./frontend01

# -hide-all-plugin-packages + -package (this should not work!)
.PHONY: T11244
T11244:
	! "$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) --make -v0 -O T11244.hs -package-db rule-defining-plugin/pkg.T11244/local.package.conf -hide-all-plugin-packages -package rule-defining-plugin -fplugin=RuleDefiningPlugin

.PHONY: T12567a
T12567a:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) --make T12567a.hs -package-db simple-plugin/pkg.T12567a/local.package.conf -hide-all-plugin-packages -plugin-package simple-plugin 1>&2
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) --make T12567a.hs -package-db simple-plugin/pkg.T12567a/local.package.conf -hide-all-plugin-packages -plugin-package simple-plugin 1>&2
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) --make T12567b.hs -package-db simple-plugin/pkg.T12567a/local.package.conf -hide-all-plugin-packages -plugin-package simple-plugin 1>&2

.PHONY: T14335
T14335:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) -fexternal-interpreter --make -v0 plugins01.hs -package-db simple-plugin/pkg.plugins01/local.package.conf -fplugin Simple.Plugin -fplugin-opt Simple.Plugin:Irrelevant_Option -hide-all-plugin-packages -plugin-package simple-plugin
	./plugins01

# Shouldn't recompile the module
.PHONY: plugin-recomp-pure
plugin-recomp-pure:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) plugin-recomp-test.hs -package-db plugin-recomp/pkg.plugins01/local.package.conf -fplugin PurePlugin
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) plugin-recomp-test.hs -package-db plugin-recomp/pkg.plugins01/local.package.conf -fplugin PurePlugin

# Should recompile the module
.PHONY: plugin-recomp-impure
plugin-recomp-impure:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) plugin-recomp-test.hs -package-db plugin-recomp/pkg.plugins01/local.package.conf -fplugin ImpurePlugin
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) plugin-recomp-test.hs -package-db plugin-recomp/pkg.plugins01/local.package.conf -fplugin ImpurePlugin

# Should not recompile the module the first time but should the second time
.PHONY: plugin-recomp-flags
plugin-recomp-flags:
	"$(TEST_HC)" $(TEST_HC_OPTS)  $(ghcPluginWayFlags) plugin-recomp-test.hs -package-db plugin-recomp/pkg.plugins01/local.package.conf -fplugin FingerprintPlugin -fplugin-opt FingerprintPlugin:0
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) plugin-recomp-test.hs -package-db plugin-recomp/pkg.plugins01/local.package.conf -fplugin FingerprintPlugin -fplugin-opt FingerprintPlugin:0
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) plugin-recomp-test.hs -package-db plugin-recomp/pkg.plugins01/local.package.conf -fplugin FingerprintPlugin -fplugin-opt FingerprintPlugin:1
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) plugin-recomp-test.hs -package-db plugin-recomp/pkg.plugins01/local.package.conf -fplugin FingerprintPlugin -fplugin-opt FingerprintPlugin:1

# Should recompile the module because the plugin changed
.PHONY: plugin-recomp-change
plugin-recomp-change:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) -v0 plugin-recomp-test.hs -package-db plugin-recomp/pkg.plugins01/local.package.conf -fplugin PurePlugin
	"$(MAKE)" -s --no-print-directory -C plugin-recomp package.plugins01 TOP=$(TOP) RUN=-DRUN2
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) -v0 plugin-recomp-test.hs -package-db plugin-recomp/pkg.plugins01/local.package.conf -fplugin PurePlugin

# Should recompile the module because the plugin changed, test for 15492
.PHONY: plugin-recomp-change-prof
plugin-recomp-change-prof:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) -v0 plugin-recomp-test.hs -package-db plugin-recomp/pkg.plugins01/local.package.conf -fplugin PurePlugin
	"$(TEST_HC)" $(TEST_HC_OPTS) -prof -osuf p_o -hisuf p_hi -v0 plugin-recomp-test.hs -package-db plugin-recomp/pkg.plugins01/local.package.conf -fplugin PurePlugin
	"$(MAKE)" -s --no-print-directory -C plugin-recomp package.plugins01 TOP=$(TOP) RUN=-DRUN2
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) -v0 plugin-recomp-test.hs -package-db plugin-recomp/pkg.plugins01/local.package.conf -fplugin PurePlugin
	"$(TEST_HC)" $(TEST_HC_OPTS) -prof -osuf p_o -hisuf p_hi -v0 plugin-recomp-test.hs -package-db plugin-recomp/pkg.plugins01/local.package.conf -fplugin PurePlugin

.PHONY: T16104
T16104:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) -v0 T16104.hs -package-db T16104-plugin/pkg.T16104-plugin/local.package.conf

.PHONY: T16260
T16260:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) -v0 T16260.hs -package-db simple-plugin/pkg.T16260/local.package.conf -fplugin Simple.TrustworthyPlugin
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) -v0 T16260.hs -package-db simple-plugin/pkg.T16260/local.package.conf -fplugin Simple.TrustworthyPlugin -fplugin-trustworthy

.PHONY: T19926
T19926:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) -v0 T19926.hs -package-db simple-plugin/pkg.T19926/local.package.conf -fplugin Simple.DefaultPlugin
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) -v0 T19926.hs -package-db simple-plugin/pkg.T19926/local.package.conf -fplugin Simple.DefaultPlugin -fplugin-trustworthy

.PHONY: HoleFitPlugin
HoleFitPlugin:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) -v0 HoleFitPlugin.hs -package-db hole-fit-plugin/pkg.hole-fit-plugin/local.package.conf

# Should recompile the module because the plugin changed
.PHONY: plugin-recomp-change-2
plugin-recomp-change-2:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) -v0 plugin-recomp-test.hs PluginRecompTest.hs -package-db plugin-recomp/pkg.plugins01/local.package.conf -fplugin PurePlugin
	"$(MAKE)" -s --no-print-directory -C plugin-recomp package.plugins01 TOP=$(TOP) RUN=-DRUN2
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) -v0 plugin-recomp-test.hs PluginRecompTest.hs -package-db plugin-recomp/pkg.plugins01/local.package.conf -fplugin PurePlugin

# Shouldn't recompile the module because the plugin is pure and nothing changed.
.PHONY: T20417
T20417:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) -v0 plugin-recomp-test.hs -package-db plugin-recomp/pkg.plugins01/local.package.conf -hide-all-packages -package base -plugin-package plugin-recompilation-0.1  -fplugin PurePlugin
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) -v0 plugin-recomp-test.hs -package-db plugin-recomp/pkg.plugins01/local.package.conf -hide-all-packages -package base -plugin-package plugin-recompilation-0.1 -fplugin PurePlugin

# Test that we don't link plugin with target code
.PHONY: T20218
T20218:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) -v4 T20218.hs -package-db simple-plugin/pkg.T20218/local.package.conf -fplugin Simple.Plugin -plugin-package simple-plugin

# T20218b tests that we correctly link with plugins passed with -package
.PHONY: T20218b
T20218b:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) T20218b.hs -package-db simple-plugin/pkg.T20218b/local.package.conf -fplugin Simple.ReplacePlugin -package simple-plugin -v0
	./T20218b

.PHONY: test-defaulting-plugin
test-defaulting-plugin:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) -v0 test-defaulting-plugin.hs -package-db defaulting-plugin/pkg.test-defaulting-plugin/local.package.conf

.PHONY: test-defaulting-plugin-fail
test-defaulting-plugin-fail:
	-"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) -v0 test-defaulting-plugin-fail.hs -package-db defaulting-plugin/pkg.test-defaulting-plugin-fail/local.package.conf

.PHONY: T23821
T23821:
	-"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) --make -v0 T23821.hs -package-db defaulting-plugin/pkg.test-defaulting-plugin/local.package.conf

.PHONY: plugins-order
plugins-order:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) --make -v0 plugins-order.hs -package-db plugin-recomp/pkg.plugins01/local.package.conf -fplugin ImpurePlugin -fplugin PurePlugin -fplugin-opt ImpurePlugin:First_Option -fplugin-opt PurePlugin:Second_Option -fplugin-opt PurePlugin:Second_Option_2 -fplugin FingerprintPlugin -fplugin-opt FingerprintPlugin:1
	./plugins-order

.PHONY: plugins-order-pragma
plugins-order-pragma:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) --make -v0 plugins-order-pragma.hs -package-db plugin-recomp/pkg.plugins01/local.package.conf -fplugin ImpurePlugin
	./plugins-order-pragma

.PHONY: T20803a
T20803a:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) --make -v0 T20803a.hs -package-db T20803-plugin/pkg.T20803a/local.package.conf

.PHONY: T20803b
T20803b:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) --make -v0 T20803b.hs -package-db T20803-plugin/pkg.T20803b/local.package.conf

.PHONY: test-echo-in-turn
test-echo-in-turn:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) -v0 test-echo-in-turn.hs -package-db echo-plugin/pkg.test-echo-in-turn/local.package.conf

.PHONY: test-echo-in-line
test-echo-in-line:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) -v0 test-echo-in-line.hs -package-db echo-plugin/pkg.test-echo-in-line/local.package.conf

.PHONY: test-echo-in-turn-many-args
test-echo-in-turn-many-args:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) -v0 test-echo-in-turn-many-args.hs -package-db echo-plugin/pkg.test-echo-in-turn-many-args/local.package.conf

.PHONY: test-echo-in-line-many-args
test-echo-in-line-many-args:
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) -v0 test-echo-in-line-many-args.hs -package-db echo-plugin/pkg.test-echo-in-line-many-args/local.package.conf


ifeq "$(WINDOWS)" "YES"
DLL = $1.dll
else ifeq "$(DARWIN)" "YES"
DLL = lib$1.dylib
else
DLL = lib$1.so
endif

.PHONY: plugins-external
plugins-external:
	cp shared-plugin/pkg.plugins01/dist/build/$(call DLL,HSsimple-plugin*) $(call DLL,HSsimple-plugin)
	"$(TEST_HC)" $(TEST_HC_OPTS) $(ghcPluginWayFlags) --make -v0 -fplugin-library "$(PWD)/$(call DLL,HSsimple-plugin);simple-plugin-1234;Simple.Plugin;[\"Plugin\",\"loaded\",\"from\",\"a shared lib\"]" plugins-external.hs
	./plugins-external
