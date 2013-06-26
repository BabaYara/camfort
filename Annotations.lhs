> {-# LANGUAGE DeriveDataTypeable #-}
> {-# LANGUAGE MultiParamTypeClasses #-}
> {-# LANGUAGE TypeSynonymInstances #-}
> {-# LANGUAGE FlexibleInstances #-}

> module Annotations where

> import Data.Data
> import Data.Generics.Uniplate.Operations

> import Data.Map.Lazy hiding (map)

> import Language.Fortran

> import Debug.Trace

> import Language.Fortran.Pretty

> import Language.Haskell.ParseMonad 
> import Language.Haskell.Syntax (SrcLoc(..))

Loop classifications 

> data ReduceType = Reduce | NoReduce
> data AccessPatternType = Regular | RegularAndConstants | Irregular | Undecidable 
> data LoopType = Functor ReduceType | Gather ReduceType ReduceType AccessPatternType | Scatter ReduceType AccessPatternType

 classify :: Fortran Annotation -> Fortran Annotation
 classify x = 

> data Annotation = A {indices :: [Variable],
>                      lives ::([Variable],[Variable]),
>                      arrsRead :: Map Variable [[Expr ()]], 
>                      arrsWrite :: Map Variable [[Expr ()]],
>                      number :: Int,
>                      refactored :: Maybe SrcLoc, 
>                      successorStmts :: [Int]}
>                    deriving (Eq, Show, Typeable, Data)

 -- Map Variable [[(Variable,Int)]],

> pRefactored :: Annotation -> Bool
> pRefactored x = case (refactored x) of
>                   Nothing -> False
>                   Just _  -> True

> unitAnnotation = A [] ([], []) empty empty 0 Nothing []

