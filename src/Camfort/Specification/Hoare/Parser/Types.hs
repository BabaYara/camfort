{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE LambdaCase         #-}
{-# OPTIONS_GHC -Wall #-}

module Camfort.Specification.Hoare.Parser.Types where

import           Control.Monad.Except
import           Data.Data
import           Control.Exception
import           Data.List                         (intercalate)

import qualified Data.ByteString.Char8             as B

import qualified Language.Fortran.AST              as F
import qualified Language.Fortran.Lexer.FreeForm   as F
import qualified Language.Fortran.Parser.Fortran90 as F
import qualified Language.Fortran.ParserMonad      as F


data HoareParseError
  = UnmatchedQuote
  | UnexpectedInput
  | MalformedExpression String
  | ParseError [Token]
  | LexError String
  deriving (Eq, Ord, Typeable, Data)

instance Show HoareParseError where
  show UnmatchedQuote = "unmatched quote"
  show UnexpectedInput = "unexpected characters in input"
  show (MalformedExpression expr) = "couldn't parse expression: \"" ++ expr ++ "\""
  show (ParseError tokens) = "unable to parse input: " ++ prettyTokens tokens
  show (LexError xs) = "unable to lex input: " ++ xs

instance Exception HoareParseError where

prettyTokens :: [Token] -> String
prettyTokens = intercalate " " . map prettyToken
  where
    prettyToken = \case
      TExpr expr -> "\"" ++ expr ++ "\""
      TStaticAssert -> "static_assert"
      TPre -> "pre"
      TPost -> "post"
      TInvariant -> "invariant"
      TSeq -> "seq"
      TRParen -> ")"
      TLParen -> "("
      TAnd -> "&"
      TOr -> "|"
      TImpl -> "->"
      TEquiv -> "<->"
      TNot -> "!"
      TTrue -> "T"
      TFalse -> "F"

type HoareSpecParser = Either HoareParseError

data Token
  = TExpr String
  | TStaticAssert
  | TPre
  | TPost
  | TInvariant
  | TSeq
  | TRParen
  | TLParen
  | TAnd
  | TOr
  | TImpl
  | TEquiv
  | TNot
  | TTrue
  | TFalse
  deriving (Show, Eq, Ord, Typeable, Data)

-- TODO: Make this report errors and deal with source position better
parseExpression :: String -> HoareSpecParser (F.Expression ())
parseExpression expr =
  case F.runParse F.statementParser parseState of
    F.ParseOk (F.StExpressionAssign _ _ _ e) _ -> return e
    _ -> throwError (MalformedExpression expr)
  where
    paddedExpr = B.pack $ "      a = " ++ expr
    parseState = F.initParseState paddedExpr F.Fortran90 "<unknown>"
