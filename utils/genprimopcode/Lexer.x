{
module Lexer (lex_tok) where

import ParserM (ParserM (..), mkT, mkTv, Token(..), start_code,
                set_start_code,
                inc_brace_depth, dec_brace_depth,
                show_pos, position,
                AlexInput, alexGetByte)
import qualified ParserM as ParserM (input)
}

words :-

    <0>         $white+             ;
    <0>         "--" [^\n]* \n      ;
                "{"                 { \i -> do {
                                                set_start_code in_braces;
                                                inc_brace_depth;
                                                mkT TOpenBrace i
                                               }
                                    }
                "}"                 { \i -> do {
                                                dec_brace_depth;
                                                mkT TCloseBrace i
                                               }
                                    }
    <0>         "->"                { mkT TArrow }
    <0>         "=>"                { mkT TDArrow }
    <0>         "="                 { mkT TEquals }
    <0>         ","                 { mkT TComma }
    <0>         "("                 { mkT TOpenParen }
    <0>         ")"                 { mkT TCloseParen }
    <0>         "(#"                { mkT TOpenParenHash }
    <0>         "#)"                { mkT THashCloseParen }
    <0>         "["                 { mkT TOpenBracket }
    <0>         "]"                 { mkT TCloseBracket }
    <0>         "<"                 { mkT TOpenAngle }
    <0>         ">"                 { mkT TCloseAngle }
    <0>         "section"           { mkT TSection }
    <0>         "primop"            { mkT TPrimop }
    <0>         "pseudoop"          { mkT TPseudoop }
    <0>         "primtype"          { mkT TPrimtype }
    <0>         "with"              { mkT TWith }
    <0>         "defaults"          { mkT TDefaults }
    <0>         "True"              { mkT TTrue }
    <0>         "False"             { mkT TFalse }
    <0>         "Compare"           { mkT TCompare }
    <0>         "GenPrimOp"         { mkT TGenPrimOp }
    <0>         "fixity"            { mkT TFixity }
    <0>         "infix"             { mkT TInfixN }
    <0>         "infixl"            { mkT TInfixL }
    <0>         "infixr"            { mkT TInfixR }
    <0>         "Nothing"           { mkT TNothing }
    <0>         "vector"            { mkT TVector }
    <0>         "bytearray_access_ops" { mkT TByteArrayAccessOps }
    <0>         "addr_access_ops"   { mkT TAddrAccessOps }
    <0>         "thats_all_folks"   { mkT TThatsAllFolks }
    <0>         "SCALAR"            { mkT TSCALAR }
    <0>         "VECTOR"            { mkT TVECTOR }
    <0>         "VECTUPLE"          { mkT TVECTUPLE }
    <0>         [a-z][a-zA-Z0-9\#_]* { mkTv TLowerName }
    <0>         [A-Z][a-zA-Z0-9\#_]* { mkTv TUpperName }
    <0>         \-? [0-9][0-9]*     { mkTv (TInteger . read) }
    <0>         \" [^\"]* \"        { mkTv (TString . tail . init) }
    <in_braces> [^\{\}]+            { mkTv TNoBraces }
    <in_braces> \n                  { mkTv TNoBraces }

{
get_tok :: ParserM Token
get_tok = ParserM $ \i st ->
   case alexScan i (start_code st) of
       AlexEOF -> Right (i, st, TEOF)
       AlexError _ -> Left ("Lexical error at " ++ show_pos (position i))
       AlexSkip i' _ -> case get_tok of
                            ParserM f -> f i' st
       AlexToken i' l a -> case a $ take l $ ParserM.input i of
                               ParserM f -> f i' st

lex_tok :: (Token -> ParserM a) -> ParserM a
lex_tok cont = get_tok >>= cont
}
