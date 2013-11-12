> {-# LANGUAGE QuasiQuotes #-}
> {-# LANGUAGE FlexibleInstances #-}
> {-# LANGUAGE UndecidableInstances #-}
> {-# LANGUAGE OverlappingInstances #-}
> {-# LANGUAGE ImplicitParams #-}
> {-# LANGUAGE MultiParamTypeClasses #-}

> {-# LANGUAGE OverlappingInstances #-}
> {-# LANGUAGE KindSignatures #-}

> {-# LANGUAGE FlexibleContexts #-}
> {-# LANGUAGE ScopedTypeVariables #-}


> {-# LANGUAGE DeriveGeneric #-}
> {-# LANGUAGE DeriveDataTypeable #-}

> module Output where

> import Helpers
> import Traverse

> import Analysis.Annotations
> import Language.Fortran as Fortran
> import Language.Fortran.Pretty

> import Data.Text hiding (foldl,map, concatMap,take,drop)
> import qualified Data.Text as Text 
> import Data.Map.Lazy hiding (map, foldl)
> import Data.Generics
> import GHC.Generics
> import Data.Generics.Uniplate.Data

> import Generics.Deriving.Copoint

> import Data.Char

> import Language.Haskell.Syntax (SrcLoc(..), srcLine, srcColumn)
> import Data.Generics.Zipper

> import Data.Maybe

> import Debug.Trace


> purple = "#800080"
> green = "#008000"
> blue = "#000080"

> keyword = map pack
>           ["end","subroutine","function","program","module","block","data", "common",
>            "namelist", "external", "interface", "type", "include",
>            "len", "kind", "dimension", "allocatable", "parameter", "external",
>            "intent", "intrinsic", "optional", "pointer", "save", "target",
>            "volatile", "public", "private", "sequence", "operator", "assignment",
>            "procedure", "do", "if", "else", "then", "allocate", "backspace", 
>            "call", "open", "close", "continue", "cycle", "deallocate", "endfile",
>            "exit", "forall", "goto", "nullify", "inquire", "rewind", "stop", "where",
>            "write", "reurn", "print", "read", "write", "implicit", "use"]

> addColor c k = "<span style='color:" ++ c ++ "'>" ++ k ++ "</span>"
> toColor c t k = replace k (Text.concat [pack ("<span style='color:" ++ c ++ "'>"), k, pack "</span>"]) t

> types = map pack ["real", "integer", "character", "type", "logical"]

> pre l = Text.concat [pack "<pre>", l, pack "</pre>"]

> outputHTML :: forall p . (Data p, Typeable p, OutputG p Alt2, OutputIndG (Fortran p) Alt2, Indentor (Decl p), Indentor (Fortran p)) => Fortran.ProgUnit p -> String
> outputHTML prog = unpack html
>                 where
>                   t :: SubName p -> SubName p
>                   t (SubName p n) = SubName p (addColor blue n)
>                   t x = x
                  

>                   html = let ?variant = Alt2
>                          in 
>                            (Text.append (pack "<head><script type='text/javascript' src='../source.js'></script><link href='../source.css' type='text/css' rel='stylesheet' /></head>"))
>                          . (\t -> replace (pack "newline") (pack "\n") t)
>                          . (Text.concat . (map pre) . Text.lines)
>                          . (\t -> foldl (toColor green) t types)
>                          . (\t -> foldl (toColor purple) t keyword)
>                          . (pack . outputF)
>                          -- . (pack . output) 
>                          -- . (pack . paraBi (\p -> \ss -> (showPara p) ++ ss) "")
>                          -- . (pack . (para (\p -> \ss -> showPara p ++ (Prelude.concat ss))))
>                          . (transformBi t) $ prog

Output routines specialised to the analysis.
                   
> instance OutputG Bool Alt2 where
>     outputG = show

> instance OutputG SrcLoc Alt2 where
>     outputG _ = "" -- not sure if I want this to shown

> instance (OutputIndG (Fortran p) Alt2, OutputG p Alt2, Indentor (Decl p), Indentor (Fortran p)) => OutputG (ProgUnit p) Alt2 where
>     outputG = outputF

> instance OutputG (SubName p) Alt2 where
>     outputG = outputF

> instance OutputG (Implicit p) Alt2 where
>     outputG = outputF

> instance (Indentor (Decl p)) => OutputG (Decl p) Alt2 where
>     outputG = outputF

> instance OutputG (Type p) Alt2 where
>     outputG = outputF

> instance OutputG (VarName p) Alt2 where
>     outputG = outputF

> instance OutputG (Expr p) Alt2 where
>     outputG = outputF

> instance OutputG (UnaryOp p) Alt2 where
>     outputG = outputF

> instance OutputG (BinOp p) Alt2 where
>     outputG = outputF

> instance OutputG (ArgList p) Alt2 where
>     outputG = outputF

> instance OutputG (BaseType p) Alt2 where
>     outputG = outputF

> instance Indentor (Decl p) => OutputG (InterfaceSpec p) Alt2 where
>     outputG = outputF

> instance OutputG (Arg p) Alt2 where
>     outputG = outputF

> instance OutputG (ArgName p) Alt2 where
>     outputG = outputF

> instance OutputG (GSpec p) Alt2 where
>     outputG = outputF

> instance OutputG (Attr p) Alt2 where
>     outputG = outputF

> instance (OutputIndG (Fortran p) Alt2, OutputG p Alt2, Indentor (Fortran p), Indentor (Decl p)) => OutputG (Block p) Alt2 where
>     outputG = outputF

> instance (OutputIndG (Fortran p) Alt2, OutputG p Alt2, Indentor (Fortran p)) => OutputG (Fortran p) Alt2 where
>                               

>     outputG (For p _ v e e' e'' f) = "do"++" "++outputG v++" = "++outputG e++", "++
>                                    outputG e'++", "++outputG e''++"\n"++
>                                    "<span style='color:#707d8f'>"++"{"++outputG p++"}</span>\n" ++ 
>                                    (outputIndG 1 f)++"\n"++(ind 1)++"end do"
>     outputG t = outputF t

> instance OutputG (Spec p) Alt2 where
>     outputG = outputF

> instance Indentor (Fortran Bool) where
>     indR t i = if (copoint t) then
>                    let (s, SrcLoc f l c) = getSpan t
>                    in Prelude.take c (repeat ' ')
>                else ind i

> instance OutputIndG (Fortran A1) Alt2 where
>     outputIndG = outputIndF

> instance OutputIndG (Fortran Annotation) Alt2 where

>     outputIndG i t@(For p _ v e e' e'' f) = (outputAnn p False i (show t)) ++ 
>                                           annotationMark i t
>                                           ((ind i) ++ "do"++" "++outputG v++" = "++
>                                            outputG e++", "++
>                                            outputG e'++", "++outputG e''++"\n"++
>                                            (outputIndG (i+1) f)++"\n"++(ind i)++"end do")

                                         
>     -- outputIndG i t@(FSeq p f1 f2) =  (outputAnn p False i) ++ outputIndG i f1 ++ outputIndG i f2
>     outputIndG i t = "<div style=''>" ++ (outputAnn (rextract t) False i (show t)) ++  (annotationMark i t (outputIndF i t)) ++ "</div>"

> annotationMark i t x = "<div class='clickable' onClick='toggle(" ++  
>                        (show $ number (rextract t)) ++ ");'>" ++
>                        x ++ "</div>"


> row xs = "<tr>" ++ (concatMap (\x -> "<td>" ++ x ++ "</td>") xs) ++ "</tr>"

> instance OutputG Annotation Alt2 where
>     outputG t = outputAnn t False 0 (show t)

> breakUp xs = (take 80 xs) ++ "newline" ++ (if (drop 80 xs) == [] then [] else breakUp (drop 80 xs))

> outputAnn t visible i astString = 
>      "<div id='a" ++ (show $ number t) ++ "' style='" ++
>      (if visible then "" else "display:none;") ++
>      "' class'outer'><div class='spacer'><pre>" ++ (indent 3 i) ++ "</pre></div>" ++ 
>      "<div class='annotation'><div class='number'>" ++ (show $ number t) ++ "</div>" ++ 
>      "<div><div class='clickable' onClick=\"toggle('" ++ (show $ number t) ++  "src');\">" ++
>      "<u>show ast</u></div><div id='a" ++ (show $ number t) ++ "src' " ++
>      "style='background:#fff;display:none;width:600px;overflow:auto;'>" ++ (breakUp astString) ++ "</div></div>" ++ "<p><table>" ++
>      row ["lives: (in) ",    showList $ (map show) $ fst $ lives t, "(out)", showList $ (map show) $ snd $ lives t] ++ 
>      row ["indices:",  showList $ indices t] ++ 
>      row ["successors:", showList $ (map show) (successorStmts t)] ++ 
>      row ["arrays R:", showExps (assocs $ arrsRead t)] ++ 
>      row ["arrays W:", showExps (assocs $ arrsWrite t)] ++
>      "</table></p></div><br />\n\r\n" 
>          where
>            listToPair x       = "(" ++ listToPair' x ++ ")"
>            listToPair' []     = ""
>            listToPair' [x]    = outputF x
>            listToPair' (x:xs) = outputF x ++ ", " ++ listToPair' xs

>            showExps []           = ""
>            showExps [(v, es)]    = "[" ++ v ++ ": " ++ (showList $ map listToPair es) ++ "]"
>            showExps ((v, es):ys) = (showExps [(v, es)]) ++ ", " ++ (showExps ys)


>            showList []  = ""
>            showList [x] = x
>            showList (x:xs) = x ++ ", " ++ showList xs


> type A1 =  Bool

> lineCol :: SrcLoc -> (Int, Int)
> lineCol x = (srcLine x, srcColumn x)

 inBounds :: SrcLoc -> (SrcLoc, SrcLoc) -> Bool
 inBounds x (l,u) = (lineCol x) >= (lineCol l) && (lineCol x) < (lineCol u)



> takeBounds (l, u) inp = takeBounds' (lineCol l, lineCol u) [] inp 


> -- dropNs is a flag to toggle dropping multiple '\n's

> 
> takeBounds' ((ll, lc), (ul, uc)) tk inp  =
>     if (ll == ul && lc == uc) || (ll > ul) then (Prelude.reverse tk, inp)
>     else case inp of []             -> (Prelude.reverse tk, inp)
>                      ([]:[])        -> (Prelude.reverse tk, inp)
>                      --([]:([]:ys)) | t && dropNs -> takeBounds'' ((ll+2, 0), (ul, uc)) ('\n':tk) ys 
>                      ([]:ys)        -> takeBounds' ((ll+1, 0), (ul, uc)) ('\n':tk) ys
>                      ((x:xs):ys)    -> takeBounds' ((ll, lc+1), (ul, uc)) (x:tk) (xs:ys) 

-- Indenting for refactored code

> instance Copointed p => Indentor (p Annotation) where
>     indR t i = case (refactored . copoint $ t) of
>                  Just (SrcLoc f _ c) -> Prelude.take c (repeat ' ')
>                  Nothing             -> ind i

GLORIOUS REFACTORING ALGORITHM!

> reprint :: SourceText -> Filename -> Program Annotation -> String
> reprint ""    f p = let ?variant = Alt1 in foldl (\a b -> a ++ "\n" ++ outputF b) "" p 
> reprint input f p = let input' = Prelude.lines input
>                         start = SrcLoc f 1 0
>                         end = SrcLoc f (Prelude.length input') (1 + (Prelude.length $ Prelude.last input'))
>                         (pn, cursorn) = reprintC start input' (toZipper p)
>                         (_, inpn) = takeBounds (start, cursorn) input'
>                         (pe, _) = takeBounds (cursorn, end) inpn
>                      in pn ++ pe

> reprintC :: SrcLoc -> [String] -> Zipper a -> (String, SrcLoc)
> reprintC cursor inp z = 
>                         let (p1, cursor', flag) = query (refactoring inp cursor) z 

>                             (_, inp') = takeBounds (cursor, cursor') inp
>                             (p2, cursor'') = if flag then ("", cursor') else enterDown cursor' inp' z
>                                              -- for debugging: ("--_" ++ show p1 ++ "\n") `trace` 

>                             (_, inp'') = takeBounds (cursor', cursor'') inp'
>                             (p3, cursor''') = enterRight cursor'' inp'' z

>                         in  (p1 ++ p2 ++ p3, cursor''')

> enterDown cursor inp z = case (down' z) of
>                              Just dz -> reprintC cursor inp dz
>                              Nothing -> ("", cursor)

> enterRight cursor inp z = case (right z) of
>                              Just rz -> reprintC cursor inp rz
>                              Nothing -> ("", cursor)


Specifies how to do specific refactorings
(uses generic query extension - remember extQ is non-symmetric)

> refactoring :: (Typeable a) => [String] -> SrcLoc -> a -> (String, SrcLoc, Bool)
> refactoring inp cursor = ((((\_ -> ("", cursor, False)) 
>                               `extQ` (refactorUses inp cursor))
>                                  `extQ` (refactorDecl inp cursor))
>                                     `extQ` (refactorArgName inp cursor))
>                                        `extQ` (refactorFortran inp cursor)


> refactorFortran :: [String] -> SrcLoc -> Fortran Annotation -> (String, SrcLoc, Bool)
> refactorFortran inp cursor e =
>        if (pRefactored $ copoint e) then 
>           let (lb, ub) = getSpan e
>               (p0, _) = takeBounds (cursor, lb) inp 
>               outE = let ?variant = Alt1 in outputF e
>               lnl = case e of (NullStmt _ _) -> (if ((p0 /= []) && Prelude.last p0 /= '\n') then "\n" else "")
>                               _              -> ""
>           in if p0 == "\n" then (outE, ub, True) else (p0 ++ outE ++ lnl, ub, True)
>        else ("", cursor, False)


> refactorDecl :: [String] -> SrcLoc -> Decl Annotation -> (String, SrcLoc, Bool)
> refactorDecl inp cursor d = 
>  let ?variant = Alt1 in
>     if (pRefactored $ copoint d) then
>        let (lb, ub) = getSpan d
>            (p0, _) = takeBounds (cursor, lb) inp
>        in (p0 ++ outputF d, ub, True)
>     else ("", cursor, False)

> refactorArgName :: [String] -> SrcLoc -> ArgName Annotation -> (String, SrcLoc, Bool)
> refactorArgName inp cursor a =
>     let ?variant = Alt1 in
>         case (refactored $ copoint a) of
>             Just lb -> let (p0, _) = takeBounds (cursor, lb) inp
>                        in (p0 ++ outputF a, lb, True)
>             Nothing -> ("", cursor, False)

> refactorUses :: [String] -> SrcLoc -> Uses Annotation -> (String, SrcLoc, Bool)
> refactorUses inp cursor u = 
>     let ?variant = Alt1 in
>         case (refactored $ copoint u) of
>            Just lb -> let (p0, _) = takeBounds (cursor, lb) inp
>                        in (p0 ++ outputF u, lb, True)
>            Nothing -> ("", cursor, False) 
> 



OLD (FLAKEY) ALGORITHM

 reprint :: String -> String -> Program A1 -> String
 reprint input f z = let input' = Prelude.lines input
                     in reprintA (SrcLoc f 1 0) (SrcLoc f (Prelude.length input') (1 + (Prelude.length $ Prelude.last input'))) input' (toZipper z)


 doHole :: (Show (d A1)) => SrcLoc -> SrcLoc -> [String] -> Zipper (d A1) -> (String, SrcLoc)
 doHole cursor end inp z = let ?variant = Alt2 in
                             case (getHole z)::(Maybe (Fortran A1)) of
                           Just e  -> let flag = copoint e
                                          (lb, ub) = getSpan e
                                          (p1, rest1) = takeBounds (cursor, lb) inp
                                      in  if flag then let ?variant = Alt2
                                                       in (p1 ++ outputF e, ub)
                                          else case (down' z) of
                                                    Just cz -> (p1 ++ reprintA lb ub rest1 cz, ub)
                                                    Nothing -> let (p2, _) = takeBounds (lb, ub) rest1
                                                               in (p1 ++ p2, ub)
                           Nothing -> case (down' z) of 
                                        Just cz -> "no - down\n" `trace` (reprintA cursor end inp cz, cursor)
                                        Nothing -> ("", cursor)

 reprintA :: (Show (d A1)) =>  SrcLoc -> SrcLoc -> [String] -> Zipper (d A1) -> String
 reprintA cursor end inp z = let (p1, cursor') = doHole cursor end inp z
                                 (p2, inp')    = takeBounds (cursor, cursor') inp
                             in p1 ++ case (right z) of 
                                         Just rz -> reprintA cursor' end inp' rz
                                         Nothing -> fst $ takeBounds (cursor', end) inp'
                                                    