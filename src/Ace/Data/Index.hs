{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TupleSections #-}

module Ace.Data.Ownership where

import           Ace.Data.Core

import           GHC.Generics (Generic)

import           P

import qualified Data.Vector as Boxed
import qualified Data.Vector.Unboxed as Unboxed
import           Data.Vector.Unboxed.Deriving (derivingUnbox)


newtype Index =
  Index {
     index :: Int
   } deriving (Eq, Ord, Show, Generic)

derivingUnbox "Index"
  [t| Index -> Int |]
  [| index |]
  [| Index |]

data IndexedRiver =
  IndexedRiver {
     indexedLower :: !Index
   , indexedHigher :: !Index
   } deriving (Eq, Ord, Show, Generic)

data Ownership =
    Unclaimed
  | ClaimedBy PunterId
    deriving (Eq, Ord, Show, Generic)

derivingUnbox "Ownership"
  [t| Ownership -> (Bool, PunterId) |]
  [| \case
       ClaimedBy p ->
         (True, p)
       Unclaimed ->
         (False, PunterId 0)
  |]
  [| \(b, p) ->
       if b then
         ClaimedBy p
       else
         Unclaimed
  |]

newtype SiteLedger =
  SiteLedger {
     siteLedger :: Unboxed.Vector SiteId
   } deriving (Eq, Ord, Show, Generic)

newtype RiverLedger =
  RiverLedger {
    riverLedger :: Boxed.Vector Indices
  } deriving (Eq, Ord, Show, Generic)

data Indices =
  Indices {
    allGone :: !Bool
    -- ^ Are all rivers connecting to this index taken?
  , ownerships :: !(Unboxed.Vector Ownership)
    -- ^ Who owns rivers connecting to this index?
  } deriving (Eq, Ord, Show, Generic)

toIndexedRiver :: River -> SiteLedger -> Maybe IndexedRiver
toIndexedRiver x ss =
  let
    source =
      riverSource x

    target =
      riverTarget x

    (lower, higher) =
      if source > target then
        (source, target)
      else
        (target, source)

    sites =
      siteLedger ss

    river
      | Just a <- Unboxed.findIndex (== lower) sites
      , Just b <- Unboxed.findIndex (== higher) sites
      = Just $ IndexedRiver (Index a) (Index b)
      | otherwise
      = Nothing
  in
    river

ownerOfIndexed :: IndexedRiver -> RiverLedger -> Ownership
ownerOfIndexed ix xs =
  let
    lower =
      index . indexedLower $ ix
    higher =
      index . indexedHigher $ ix
  in
    ownerships (riverLedger xs Boxed.! lower) Unboxed.! higher

-- | Find river candidates. /O(n^2)/ where /n/ is the number of sites.
--
riverCandidates :: RiverLedger -> Unboxed.Vector River
riverCandidates =
  let
    connect x =
      makeRiver (SiteId x) . SiteId

    go =
      flip Boxed.ifoldl Unboxed.empty $ \acc ix (Indices gone ys) ->
        if gone then
          acc
        else
          (acc Unboxed.++) .
          Unboxed.map (connect ix) .
          Unboxed.findIndices (== Unclaimed) $
            ys
  in
    go . riverLedger
