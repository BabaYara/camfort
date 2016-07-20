{-
   Copyright 2016, Dominic Orchard, Andrew Rice, Mistral Contrastin, Matthew Danish

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-}

{-# LANGUAGE RankNTypes #-}

module Camfort.Reprint where

import Data.Generics.Zipper

import Camfort.PrettyPrint
import Camfort.Analysis.Annotations
import Camfort.Traverse
import Camfort.Helpers

import qualified Data.ByteString.Char8 as B
import Data.Functor.Identity
import Data.Data
import Control.Monad.Trans.State.Lazy

import Language.Fortran
import Camfort.Analysis.Syntax

{-
Reminder:
 -- type SourceText    = B.ByteString
 -- data SrcLoc
       = SrcLoc {srcFilename :: String, srcLine :: Int, srcColumn :: Int}
-}

type Refactored = Bool

-- A refactoring takes a 'Typeable' value
-- into a stateful SourceText (ByteString) transformer,
-- which returns a pair of a stateful computation of an updated SourceText
-- paired with a boolean flag denoting whether a refactoring has been
-- performed.  The state contains a SrcLoc which is the "cursor"
-- within the original source text. The incoming value corresponds to
-- the position of the first character in the input SourceText. The
-- outgoing value is a cursor ahead of the incoming one which shows
-- the amount of SourceText that is consumed by the refactoring.

type Refactoring m =
    forall b .
     Typeable b => b -> SourceText -> StateT SrcLoc m (SourceText, Refactored)

-- The reprint algorithm takes a refactoring (parameteric in
-- some monad m) and turns an arbitrary pretty-printable type 'p'
-- into a monadic SourceText transformer.

reprint :: (Monad m, Data p, PrettyPrint p)
        => Refactoring m -> p -> SourceText -> m SourceText
reprint refactoring tree input
  -- If the inupt is null then switch into pretty printer
  | B.null input = return $ prettyPrint tree
  -- Otherwise go with the normal algorithm
  | otherwise = do
      -- Create an initial cursor at the start of the file
      let cursor0 = SrcLoc "" 1 0
      -- Enter the top-node of a zipper for 'tree'
      -- setting the cursor at the start of the file
      (output, cursorn) <- runStateT (enter refactoring (toZipper tree) input) cursor0
      -- Remove from the input the portion covered by the main algorithm
      -- leaving the rest of the file not covered within the bounds of
      -- the tree
      let (_, remaining)  = takeBounds (cursor0, cursorn) input
      return $ output `B.append` remaining

-- The enter, enterDown, enterRight each take a refactoring
-- and a zipper producing a stateful SourceText transformer with SrcLoc state.

enter, enterDown, enterRight
  :: Monad m
  => Refactoring m -> Zipper a -> SourceText -> StateT SrcLoc m SourceText

-- `enter` applies the generic refactoring to the current context
-- of the zipper
enter refactoring z inp = do

  -- Part 1.
  -- Apply a refactoring
  cursor     <- get
  (p1, refactored) <- query (flip refactoring inp) z

  -- Part 2.
  -- Cut out the portion of source text consumed by the refactoring
  cursor'    <- get
  (_, inp')  <- return $ takeBounds (cursor, cursor') inp
  -- If a refactoring was not output,
  -- Enter the children of the current context
  p2         <- if refactored
                   then return B.empty
                   else enterDown refactoring z inp'

  -- Part 3.
  -- Cut out the portion of source text consumed by the children
  -- then enter the right sibling of the current context
  cursor''   <- get
  (_, inp'') <- return $ takeBounds (cursor', cursor'') inp'
  p3         <- enterRight refactoring z inp''

  -- Conat the output for the current context, children, and right sibling
  return $ B.concat [p1, p2, p3]

-- `enterDown` navigates to the children of the current context
enterDown refactoring z inp =
  case (down' z) of
    -- Go to children
    Just dz -> enter refactoring dz inp
    -- No children
    Nothing -> return $ B.empty

-- `enterRight` navigates to the right sibling of the current context
enterRight refactoring z inp =
  case (right z) of
    -- Go to right sibling
    Just rz -> enter refactoring rz inp
    -- No right sibling
    Nothing -> return $ B.empty

-- Given a lower-bound and upper-bound pair of SrcLocs, split the
-- incoming SourceText based on the distance between the SrcLoc pairs
takeBounds :: (SrcLoc, SrcLoc) -> SourceText -> (SourceText, SourceText)
takeBounds (l, u) inp = takeBounds' (lineCol l, lineCol u) B.empty inp
takeBounds' ((ll, lc), (ul, uc)) tk inp  =
    if (ll == ul && lc == uc) || (ll > ul) then (B.reverse tk, inp)
    else
      case B.uncons inp of
         Nothing         -> (B.reverse tk, inp)
         Just ('\n', ys) -> takeBounds' ((ll+1, 0), (ul, uc)) (B.cons '\n' tk) ys
         Just (x, xs)    -> takeBounds' ((ll, lc+1), (ul, uc)) (B.cons x tk) xs