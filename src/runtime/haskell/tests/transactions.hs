import Test.HUnit
import PGF2
import PGF2.Transactions

main = do
  gr1 <- readPGF "tests/basic.pgf"
  let Just ty = readType "(N -> N) -> P (s z)"

  gr2 <- modifyPGF gr1              (createFunction "foo" ty pi)
  gr3 <- branchPGF gr1 "bar_branch" (createFunction "bar" ty pi)

  Just gr4 <- checkoutPGF gr1 "master"
  Just gr5 <- checkoutPGF gr1 "bar_branch"

  gr6 <- modifyPGF gr1 (dropFunction "ind")

  runTestTTAndExit $
    TestList $
      [TestCase (assertEqual "original functions" ["c","ind","s","z"] (functions gr1))
      ,TestCase (assertEqual "extended functions" ["c","foo","ind","s","z"] (functions gr2))
      ,TestCase (assertEqual "branched functions" ["bar","c","ind","s","z"] (functions gr3))
      ,TestCase (assertEqual "checked-out extended functions" ["c","foo","ind","s","z"] (functions gr4))
      ,TestCase (assertEqual "checked-out branched functions" ["bar","c","ind","s","z"] (functions gr5))
      ,TestCase (assertEqual "reduced functions" ["c","s","z"] (functions gr6))
      ,TestCase (assertEqual "old function type" Nothing   (functionType gr1 "foo"))
      ,TestCase (assertEqual "new function type" (Just ty) (functionType gr2 "foo"))
      ,TestCase (assertEqual "old function prob" (-log 0)  (functionProb gr1 "foo"))
      ,TestCase (assertEqual "new function prob" pi        (functionProb gr2 "foo"))
      ]