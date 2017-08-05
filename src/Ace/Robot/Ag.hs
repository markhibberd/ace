{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE TupleSections #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module Ace.Robot.Ag (
    ag
  ) where

import           Ace.Data
import           Ace.Robot.Venetian () -- lol
import           Ace.Score

import           Data.Aeson.Types (FromJSON(..), ToJSON(..))
import qualified Data.Graph.Inductive.Basic as Graph
import qualified Data.Graph.Inductive.Graph as Graph
import qualified Data.Graph.Inductive.Internal.RootPath as Graph
import           Data.Graph.Inductive.PatriciaTree (Gr)
import qualified Data.Graph.Inductive.Query.SP as Graph
import qualified Data.List as List
import           Data.Map (Map)
import qualified Data.Map as Map
import           Data.Maybe (isJust)
import qualified Data.Vector.Unboxed as Unboxed

import           GHC.Generics (Generic)

import           P

import           System.IO (IO)


data Ag =
  Ag {
      agMoves :: [Move]
    , agScores :: Map (Graph.Node, Graph.Node) Int
    } deriving (Eq, Ord, Show, Generic)

instance FromJSON Ag where
instance FromJSON PunterId where
instance FromJSON Move where
instance ToJSON Ag where
instance ToJSON PunterId where
instance ToJSON Move where

ag :: Robot Ag
ag =
  Robot "ag" init move toJSON parseJSON

init :: Setup -> IO (Initialisation Ag)
init s =
  let
    world =
      setupWorld s

    graph =
      Graph.emap (const (1 :: Int)) $ fromWorld world

    kvs =
      Map.fromList . concat .
      with (Unboxed.toList $ worldMines world) $ \mid ->
        let
          tree = Graph.spTree (siteId mid) graph
        in
          flip mapMaybe (Graph.nodes graph) $ \node ->
            case Graph.getLPathNodes node tree of
              [] ->
                Nothing
              xs ->
                let
                  n =
                    length xs - 1
                in
                  Just ((siteId mid, node), n * n)
  in
    pure $ Initialisation (Ag [] kvs) []

scorePath :: Graph.Path -> Gr SiteId (Maybe PunterId) -> Int
scorePath nodes graph0 =
  let
    graph =
      Graph.elfilter (not . isJust) graph0
  in
    sum . with (pairwise nodes) $ \edge ->
      if Graph.hasEdge graph edge then
        0
      else
        1

pairwise :: Graph.Path -> [(Graph.Node, Graph.Node)]
pairwise = \case
  [] ->
    []
  xs ->
    List.zip xs (List.tail xs)

fromPath :: Graph.Path -> Gr SiteId (Maybe PunterId) -> Maybe River
fromPath nodes graph0 =
  let
    graph =
      Graph.elfilter (not . isJust) graph0
  in
    head . flip mapMaybe (pairwise nodes) $ \edge@(n0, n1) ->
      if Graph.hasEdge graph edge then
        Just $ makeRiver (SiteId n0) (SiteId n1)
      else
        Nothing

move :: Gameplay -> State Ag -> IO (RobotMove Ag)
move g s = do
  let
    pid =
      statePunter s

    mines =
      Unboxed.toList . worldMines $ stateWorld s

    scores =
      agScores (stateData s)

    previousMoves =
      gameplay g <> agMoves (stateData s)

    graph0 =
      fromWorld $ stateWorld s

    graph1 =
      Graph.elfilter (\x -> x == Just pid || x == Nothing) $
      assignRivers previousMoves graph0

    graph1_weighted =
      Graph.emap (const (1 :: Int)) graph1

    fromTuple (n, m, x) =
      fmap (n, m,) $ fromPath x graph1

    fromPaths xs =
      case xs of
        [] ->
          pure $ RobotPass (Ag previousMoves scores)

        (_, _, x) : _ ->
          pure $ RobotClaim (Ag previousMoves scores) x

    everyMove =
      catMaybes . with previousMoves $ \x ->
        case x of
          Pass _ ->
            Nothing

          Claim _ r ->
            Just r

    everyMove1 =
      concat . with previousMoves $ \x ->
        case x of
          Pass _ ->
            []

          Claim _ r ->
            [riverSource r, riverTarget r]

    ours =
      concat . with previousMoves $ \x ->
        case x of
          Pass _ ->
            []

          Claim p r ->
            if p == pid then
              [riverSource r, riverTarget r]
            else
              []

    rivers =
      Unboxed.filter (\r -> not $ r `elem` everyMove) $ worldRivers (stateWorld s)

    -- Prefer mines we haven't visited and have two other rivers taken by other players
    mines1 =
      Unboxed.filter (\r -> (length (filter (== r) everyMove1) >= 2) && (not $ r `elem` ours)) $ worldMines (stateWorld s)

    preferedRivers =
      Unboxed.filter (\r -> riverSource r `Unboxed.elem` mines1 || riverTarget r `Unboxed.elem` mines1) $ rivers

    prefered =
      head . sortOn riverSource $ Unboxed.toList preferedRivers

  case prefered of
    Just river ->
      pure $ RobotClaim (Ag previousMoves scores) river
    Nothing ->
      fromPaths .
      mapMaybe fromTuple .
      sortOn (\(x, y, _) -> Down (x, y)) .
      concat .
      with mines $ \mid ->
      let
        tree = Graph.spTree (siteId mid) graph1_weighted
      in
        with (Graph.nodes graph1) $ \node ->
          let
            path =
              Graph.getLPathNodes node tree

            nodeScore =
              fromMaybe 0 $
                Map.lookup (siteId mid, node) scores
          in
            (nodeScore, scorePath path graph1, path)