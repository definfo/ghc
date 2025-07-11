test('rnfail001', normal, compile_fail, [''])
test('rnfail002', normal, compile_fail, [''])
test('rnfail003', normal, compile_fail, [''])
test('rnfail004', normal, compile_fail, [''])
test('rnfail007', normal, compile_fail, [''])
test('rnfail008', normal, compile_fail, [''])
test('rnfail009', normal, compile_fail, [''])
test('rnfail010', normal, compile_fail, [''])
test('rnfail011', normal, compile_fail, [''])
test('rnfail012', normal, compile_fail, [''])
test('rnfail013', normal, compile_fail, [''])

test('rnfail015', normal, compile_fail, [''])
test('rnfail016', normal, compile_fail, [''])
test('rnfail016a', normal, compile_fail, [''])
test('rnfail017', normal, compile_fail, [''])
test('rnfail018', normal, compile_fail, [''])
test('rnfail019', normal, compile_fail, [''])
test('rnfail020', normal, compile, [''])	# Succeeds now (Jan07)
test('rnfail021', normal, compile_fail, [''])
test('rnfail022', normal, compile_fail, [''])
test('rnfail023', normal, compile_fail, [''])
test('rnfail024', normal, compile_fail, [''])
test('rnfail025', normal, compile_fail, [''])
test('rnfail026', normal, compile_fail, [''])
test('rnfail027', normal, compile_fail, [''])
test('rnfail028', normal, compile_fail, [''])
test('rnfail029', normal, compile_fail, [''])
test('rnfail030', normal, compile_fail, [''])
test('rnfail031', normal, compile_fail, [''])
test('rnfail032', normal, compile_fail, [''])
test('rnfail033', normal, compile_fail, [''])
test('rnfail034', normal, compile_fail, [''])
test('rnfail035', normal, compile_fail, [''])

# Missing:
# test('rnfail037', normal, compile_fail, [''])

test('rnfail039', normal, compile_fail, [''])

test('rnfail040', [extra_files(['Rnfail040_A.hs']), normalise_version('base')], multimod_compile_fail, ['rnfail040', '-v0'])
test('rnfail041', normal, compile_fail, [''])
test('rnfail042', normal, compile_fail, [''])

test('rnfail043', [req_th,unless(doing_ghci, skip)], compile_fail, ['-v0'])
test('rnfail044', normal, compile_fail, [''])
test('rnfail045', normal, compile_fail, [''])
test('rnfail046', normal, compile_fail, [''])
test('rnfail047', [extra_files(['RnFail047_A.hs', 'RnFail047_A.hs-boot'])], multimod_compile_fail, ['rnfail047', '-v0'])
test('rnfail048', normal, compile_fail, [''])
test('rnfail049', normal, compile_fail, [''])
test('rnfail050', normal, compile_fail, [''])
test('rnfail051', normal, compile_fail, [''])
test('rnfail052', normal, compile_fail, [''])
test('rnfail053', normal, compile_fail, [''])
test('rnfail054', normal, compile_fail, [''])
test('rnfail055', [extra_files(['RnFail055.hs', 'RnFail055.hs-boot', 'RnFail055_aux.hs'])], multimod_compile_fail, ['RnFail055', '-v0'])
test('rnfail056', normal, compile_fail, [''])
test('rnfail057', normal, compile_fail, [''])
test('rnfail058', normal, compile_fail, [''])
test('rnfail059', [extra_files(['RnFail059.hs', 'RnFail059.hs-boot', 'RnFail059_aux.hs'])], multimod_compile_fail, ['RnFail059', '-v0'])

test('rn_dup', normal, compile_fail, [''])
test('T495', normal, compile_fail, [''])
test('T2490', normal, compile_fail, [''])
test('T2901', normal, compile_fail, [''])
test('T2723', normal, compile, [''])  # Warnings only
test('T2993', normal, compile_fail, [''])
test('T3265', normal, compile_fail, [''])
test('T3792', normal, compile_fail, [''])
test('T4042', normal, compile_fail, [''])

test('mc13', normal, compile_fail, [''])
test('mc14', normal, compile_fail, [''])
test('T5211', normal, compile, [''])  # Warnings only
test('T1595a', normal, compile_fail, [''])
test('T5281', normal, multimod_compile, ['T5281', '-v0'])  # Warnings only
test('T5372', [], multimod_compile_fail, ['T5372', '-v0'])
test('T5385', [], multimod_compile_fail, ['T5385', '-v0'])
test('T5513', normal, compile_fail, [''])
test('T5533', normal, compile_fail, [''])
test('T5589', normal, compile_fail, [''])
test('T5657', normal, compile_fail, [''])
test('T5745', [], multimod_compile_fail, ['T5745', '-v0'])
test('T5892a', normal, compile_fail, ['-package containers'])
test('T5892b', normal, compile_fail, ['-package containers'])
test('T5951', normal, compile_fail, [''])
test('T6018rnfail', normal, compile_fail, [''])
test('T6060', normal, compile_fail, [''])
test('T6148a', normal, compile_fail, [''])
test('T6148b', normal, compile_fail, [''])
test('T6148c', normal, compile_fail, [''])
test('T6148d', normal, compile_fail, [''])
test('T7164', normal, compile_fail, [''])
test('T7338', normal, compile_fail, [''])
test('T7338a', normal, compile_fail, [''])
test('T7454', normal, compile, [''])
test('T7906', normal, compile_fail, [''])
test('T7937', normal, compile_fail, [''])
test('T7943', normal, compile_fail, [''])
test('T8448', normal, compile_fail, [''])
test('T8149', normal, compile, [''])
test('RnStaticPointersFail01', [], compile_fail, [''])
test('RnStaticPointersFail02', [], compile_fail, [''])
test('RnStaticPointersFail03', [], compile_fail, ['-dsuppress-uniques'])
test('T9006', [], multimod_compile_fail, ['T9006', '-v0'])
test('T9156', normal, compile_fail, [''])
test('T9156_DF', normal, compile_fail, [''])
test('T9177', normal, compile_fail, [''])
test('T9177a', normal, compile_fail, [''])
test('T9436', normal, compile_fail, [''])
test('T9437', normal, compile_fail, [''])
test('T9077', normal, compile_fail, [''])
test('T9815', normal, compile_fail, [''])
test('T9815b', [extra_files(['T9815.hs'])], multimod_compile_fail, ['T9815b', '-v0'])
test('T9815ghci', normal, ghci_script, ['T9815ghci.script'])
test('T9815bghci', normal, ghci_script, ['T9815bghci.script'])

test('T9032',
     normal,
     makefile_test, [])
test('T10618', normal, compile_fail, [''])
test('T10668', normal, compile_fail, [''])
test('T5001b', normal, compile_fail, [''])
test('T10781', normal, compile_fail, [''])
test('T11071', normal, compile_fail, [''])
test('T11071a', normal, compile_fail, [''])
test('T11663', normal, compile_fail, [''])
test('T12146', normal, compile_fail, [''])
test('T12229', normal, compile, [''])
test('T12681', normal, multimod_compile_fail, ['T12681','-v0'])
test('T12686', normal, compile_fail, [''])
test('T11592', normal, compile_fail, [''])
test('T12879', normal, compile_fail, [''])
test('T13644', normal, multimod_compile_fail, ['T13644','-v0'])
test('T13568', normal, multimod_compile_fail, ['T13568','-v0'])
test('T13839b', normal, compile_fail, [''])
test('T13947', normal, compile_fail, [''])
test('T13847', normal, multimod_compile_fail, ['T13847','-v0'])
test('T14225', normal, ghci_script, ['T14225.script'])
test('T14307', normal, compile_fail, [''])
test('T14591', normal, compile_fail, [''])
test('T14907a', normal, compile_fail, [''])
test('T14907b', normal, compile_fail, [''])
test('T15539', normal, compile_fail, [''])
test('T15487', normal, multimod_compile_fail, ['T15487','-v0'])
test('T15659', normal, compile_fail, [''])
test('T15607', normal, compile_fail, [''])
test('T15611a', normal, compile_fail, [''])
test('T15611b', normal, ghci_script, ['T15611b.script'])
test('T15828', normal, compile_fail, [''])
test('T16002', normal, compile_fail, [''])
test('T16114', normal, compile_fail, [''])
test('T16116b', normal, compile_fail, [''])
test('ExplicitForAllRules2', normal, compile_fail, [''])
test('T15957_Fail', normal, compile_fail, ['-Werror -Wall -Wno-missing-signatures'])
test('T16385', normal, compile_fail, [''])
test('T16504', normal, compile_fail, [''])
test('T14548', normal, compile_fail, [''])
test('T16610', normal, compile_fail, [''])
test('T17593', normal, compile_fail, [''])
test('T18021', normal, compile_fail, [''])
test('T18145', normal, compile_fail, [''])
test('T18240a', normal, compile_fail, [''])
test('T18240b', normal, compile_fail, [''])
test('T18740a', normal, compile_fail, [''])
test('T18740b', normal, compile_fail, [''])
test('T19781', [extra_files(['T19781_A.hs', 'T19781_A.hs-boot'])], multimod_compile_fail, ['T19781', '-v0'])
test('T19843a', normal, compile_fail, [''])
test('T19843b', normal, compile_fail, [''])
test('T19843c', normal, compile_fail, [''])
test('T19843d', normal, compile_fail, [''])
test('T19843e', normal, compile_fail, [''])
test('T19843f', normal, compile_fail, [''])
test('T19843g', normal, compile_fail, [''])
test('T19843h', normal, compile_fail, [''])
test('T19843i', normal, compile_fail, [''])
test('T19843j', normal, compile_fail, [''])
test('T19843k', normal, compile_fail, [''])
test('T19843l', normal, compile_fail, [''])
test('T19843m', normal, compile_fail, [''])
test('T11167_ambig', normal, compile_fail, [''])
test('T18138', normal, compile_fail, [''])
test('T20147', normal, compile_fail, [''])
test('RnEmptyStatementGroup1', normal, compile_fail, [''])
test('RnImplicitBindInMdoNotation', normal, compile_fail, [''])
test('T21605a', normal, compile_fail, [''])
test('T21605b', normal, compile_fail, [''])
test('T21605c', normal, compile_fail, [''])
test('T21605d', normal, compile_fail, [''])
test('T22839', normal, compile_fail, [''])
test('T23301', normal, compile_fail, [''])
test('RnPatternSynonymFail', req_th, compile_fail, [''])
test('RnMultipleFixityFail', normal, compile_fail, [''])
test('RnEmptyCaseFail', normal, compile_fail, [''])
test('RnDefaultSigFail', normal, compile_fail, [''])
test('RnMultipleMinimalPragmaFail', normal, compile_fail, [''])
test('RnUnexpectedStandaloneDeriving', normal, compile_fail, [''])
test('RnStupidThetaInGadt', normal, compile_fail, [''])
test('PackageImportsDisabled', normal, compile_fail, [''])
test('ImportLookupIllegal', normal, compile_fail, [''])
test('SimilarNamesImport', [extra_files(['SimilarNamesImport_aux.hs'])], multimod_compile_fail, ['SimilarNamesImport', '-v0'])
test('T23510a', normal, compile_fail, [''])
test('T16635a', normal, compile_fail, [''])
test('T16635b', normal, compile_fail, [''])
test('T16635c', normal, compile_fail, [''])
test('T23512a', normal, compile_fail, [''])
test('DifferentExportWarnings', normal, multimod_compile_fail, ['DifferentExportWarnings', '-v0'])
