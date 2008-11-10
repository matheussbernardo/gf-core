module GF.Text.Lexing (stringOp) where

import GF.Text.Transliterations
import GF.Text.UTF8
import GF.Text.CP1251

import Data.Char
import Data.List (intersperse)

-- lexers and unlexers - they work on space-separated word strings

stringOp :: String -> Maybe (String -> String)
stringOp name = case name of
  "chars"      -> Just $ appLexer (filter (not . all isSpace) . map return)
  "lextext"    -> Just $ appLexer lexText
  "lexcode"    -> Just $ appLexer lexCode
  "lexmixed"   -> Just $ appLexer lexMixed
  "words"      -> Just $ appLexer words
  "bind"       -> Just $ appUnlexer bindTok
  "unchars"    -> Just $ appUnlexer concat
  "unlextext"  -> Just $ appUnlexer unlexText
  "unlexcode"  -> Just $ appUnlexer unlexCode
  "unlexmixed" -> Just $ appUnlexer unlexMixed
  "unwords"    -> Just $ appUnlexer unwords
  "to_html"    -> Just wrapHTML
  "to_utf8"    -> Just encodeUTF8
  "from_utf8"  -> Just decodeUTF8
  "to_cp1251"  -> Just encodeCP1251
  "from_cp1251" -> Just decodeCP1251
  _ -> transliterate name

appLexer :: (String -> [String]) -> String -> String
appLexer f = unwords . filter (not . null) . f

appUnlexer :: ([String] -> String) -> String -> String
appUnlexer f = unlines . map (f . words) . lines

wrapHTML :: String -> String
wrapHTML = unlines . tag . intersperse "<br>" . lines where
  tag ss = "<html>":"<head>":"<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\" />":"</head>":"<body>" : ss ++ ["</body>","</html>"]

lexText :: String -> [String]
lexText = uncap . lext where
  lext s = case s of
    c:cs | isMajorPunct c -> [c] : uncap (lext cs)
    c:cs | isMinorPunct c -> [c] : lext cs
    c:cs | isSpace c ->       lext cs
    _:_ -> let (w,cs) = break (\x -> isSpace x || isPunct x) s in w : lext cs
    _ -> [s]
  uncap s = case s of
    (c:cs):ws -> (toLower c : cs):ws
    _ -> s

-- | Haskell lexer, usable for much code
lexCode :: String -> [String]
lexCode ss = case lex ss of
  [(w@(_:_),ws)] -> w : lexCode ws
  _ -> []

-- | LaTeX style lexer, with "math" environment using Code between $...$
lexMixed :: String -> [String]
lexMixed = concat . alternate False where
  alternate env s = case s of
    _:_ -> case break (=='$') s of
      (t,[])  -> lex env t : []
      (t,c:m) -> lex env t : [[c]] : alternate (not env) m
    _ -> []
  lex env = if env then lexCode else lexText

bindTok :: [String] -> String
bindTok ws = case ws of
    w:"&+":ws2 -> w ++ bindTok ws2
    w:[]       -> w
    w:ws2      -> w ++ " " ++ bindTok ws2
    []         -> ""

unlexText :: [String] -> String
unlexText = cap . unlext where
  unlext s = case s of
    w:[] -> w
    w:[c]:[] | isPunct c -> w ++ [c]
    w:[c]:cs | isMajorPunct c -> w ++ [c] ++ " " ++ cap (unlext cs)
    w:[c]:cs | isMinorPunct c -> w ++ [c] ++ " " ++ unlext cs
    w:ws -> w ++ " " ++ unlext ws
    _ -> []
  cap s = case s of
     c:cs -> toUpper c : cs
     _ -> s

unlexCode :: [String] -> String
unlexCode s = case s of
  w:[] -> w
  [c]:cs | isParen c -> [c] ++ unlexCode cs
  w:cs@([c]:_) | isClosing c -> w ++ unlexCode cs
  w:ws -> w ++ " " ++ unlexCode ws
  _ -> []


unlexMixed :: [String] -> String
unlexMixed = concat . alternate False where
  alternate env s = case s of
    _:_ -> case break (=="$") s of
      (t,[])  -> unlex env t : []
      (t,c:m) -> unlex env t : sep env c : alternate (not env) m
    _ -> []
  unlex env = if env then unlexCode else unlexText
  sep env c = if env then c ++ " " else " " ++ c

isPunct = flip elem ".?!,:;"
isMajorPunct = flip elem ".?!"
isMinorPunct = flip elem ",:;"
isParen = flip elem "()[]{}"
isClosing = flip elem ")]}"
