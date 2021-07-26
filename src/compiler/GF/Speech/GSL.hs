----------------------------------------------------------------------
-- |
-- Module      : GF.Speech.GSL
--
-- This module prints a CFG as a Nuance GSL 2.0 grammar.
--
-----------------------------------------------------------------------------

module GF.Speech.GSL (gslPrinter) where
import Prelude hiding ((<>)) -- GHC 8.4.1 clash with Text.PrettyPrint

--import GF.Data.Utilities
import GF.Grammar.CFG
import GF.Speech.SRG
import GF.Speech.RegExp
import GF.Infra.Option
--import GF.Infra.Ident
import PGF

import Data.Char (toUpper,toLower)
import Data.List (partition)
import GF.Text.Pretty

width :: Int
width = 75

gslPrinter :: Options -> PGF -> CId -> String
gslPrinter opts pgf cnc = renderStyle st $ prGSL $ makeNonLeftRecursiveSRG opts pgf cnc
  where st = style { lineLength = width }

prGSL :: SRG -> Doc
prGSL srg = header $++$ mainCat $++$ foldr ($++$) empty (map prRule (srgRules srg))
    where
    header = ";GSL2.0" $$
             comment ("Nuance speech recognition grammar for " ++ srgName srg) $$
             comment ("Generated by GF")
    mainCat = ".MAIN" <+> prCat (srgStartCat srg)
    prRule (SRGRule cat rhs) = prCat cat <+> union (map prAlt rhs)
    -- FIXME: use the probability
    prAlt (SRGAlt mp _ rhs) = prItem rhs


prItem :: SRGItem -> Doc
prItem = f
  where
    f (REUnion xs) = (if null es then empty else pp "?") <> union (map f nes)
      where (es,nes) = partition isEpsilon xs
    f (REConcat [x]) = f x
    f (REConcat xs) = "(" <> fsep (map f xs) <> ")"
    f (RERepeat x)  = "*" <> f x
    f (RESymbol s)  = prSymbol s

union :: [Doc] -> Doc
union [x] = x
union xs = "[" <> fsep xs <> "]"

prSymbol :: Symbol SRGNT Token -> Doc
prSymbol = symbol (prCat . fst) (doubleQuotes . showToken)

-- GSL requires an upper case letter in category names
prCat :: Cat -> Doc
prCat = pp . firstToUpper


firstToUpper :: String -> String
firstToUpper [] = []
firstToUpper (x:xs) = toUpper x : xs

{-
rmPunctCFG :: CGrammar -> CGrammar
rmPunctCFG g = [CFRule c (filter keepSymbol ss) n | CFRule c ss n <- g]

keepSymbol :: Symbol c Token -> Bool
keepSymbol (Tok t) = not (all isPunct (prt t))
keepSymbol _ = True
-}

-- Nuance does not like upper case characters in tokens
showToken :: Token -> Doc
showToken = pp . map toLower

--isPunct :: Char -> Bool
--isPunct c = c `elem` "-_.:;.,?!()[]{}"

comment :: String -> Doc
comment s = ";" <+> s


-- Pretty-printing utilities

emptyLine :: Doc
emptyLine = pp ""

($++$) :: Doc -> Doc -> Doc
x $++$ y = x $$ emptyLine $$ y
