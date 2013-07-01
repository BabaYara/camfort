> {-# LANGUAGE FlexibleInstances #-}
> {-# LANGUAGE FlexibleContexts #-}
> {-# LANGUAGE ScopedTypeVariables #-}
> {-# LANGUAGE DeriveGeneric #-}

> module DeadCode where

> import Annotations
> import LVA
> import Syntax
> import Traverse
> import Language.Fortran

> import Generics.Deriving.Copoint
> import GHC.Generics

> import Debug.Trace

> import Data.Generics.Uniplate.Operations

> deadCode :: Bool -> [Program Annotation] -> (Report, [Program Annotation])
> deadCode flag p = let (r, p') = mapM (transformBiM (elimDead flag)) (map lva p)
>                   in if r == "" then (r, p')
>                                 else (r, p') >>= (deadCode flag)

> elimDead :: Bool -> Fortran Annotation -> (Report, Fortran Annotation)
> elimDead flag x@(Assg a sp@(s1, s2) e1 e2) | (pRefactored a) == flag =
>        let lOut = liveOut a
>           -- currently assumes an assign defines only one access (which is usual)
>        in if ((varExprToAccesses e1) == []) || ((head $ varExprToAccesses e1) `elem` lOut) then 
>               return x
>           else let report = "o" ++ (show . srcLineCol $ s1) ++ ": removed dead code\n"
>                in (report, NullStmt (a { refactored = (Just s1) }) (dropLine sp))
> elimDead _ x = return x
>               