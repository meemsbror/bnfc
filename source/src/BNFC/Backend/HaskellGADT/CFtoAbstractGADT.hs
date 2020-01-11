{-
    BNF Converter: GADT Abstract syntax Generator
    Copyright (C) 2004-2005  Author:  Markus Forberg, Björn Bringert

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, 51 Franklin Street, Fifth Floor, Boston, MA 02110-1335, USA
-}

{-# LANGUAGE PatternGuards #-}

module BNFC.Backend.HaskellGADT.CFtoAbstractGADT (cf2Abstract) where

import Data.List (intercalate, nub)

import BNFC.CF
import BNFC.Backend.HaskellGADT.HaskellGADTCommon
import BNFC.Backend.Haskell.Utils
import BNFC.Backend.Haskell.CFtoAbstract (definedRules)
import BNFC.Options
import BNFC.Utils ((+++), when)


cf2Abstract :: TokenText -> String -> CF -> String -> String
cf2Abstract tokenText name cf composOpMod = unlines $ concat $
  [ [ "{-# LANGUAGE GADTs, KindSignatures, DataKinds #-}"
    , "{-# LANGUAGE EmptyCase #-}"
    , ""
    , "module" +++ name +++ "(" ++ intercalate ", " exports ++ ")" +++ "where"
    , ""
    , "import Prelude (Char, String, Integer, Double, (.), (>), (&&), (==))"
    , "import qualified Prelude as P"
    , "import qualified Data.Monoid as P"
    , ""
    , "import " ++ composOpMod
    ]
  , tokenTextImport tokenText
  , [ ""
    , "-- Haskell module generated by the BNF converter"
    , ""
    ]
  , prDummyTypes cf
  , [""]
  , prTreeType tokenText cf
  , [""]
  , prCompos cf
  , [""]
  , prShow cf
  , [""]
  , prEq cf
  , [""]
  , prOrd cf
  , [""]
  , map ((++ "\n") . show) $ definedRules False cf
  ]
  where
    exports = concat $
      [ [ "Tree(..)" ]
      , getTreeCats cf
      , map mkDefName $ getDefinitions cf
      , [ "johnMajorEq"
        , "module " ++ composOpMod
        ]
      ]

getTreeCats :: CF -> [String]
getTreeCats cf = nub $ map show $ filter (not . isList) $ map consCat $ cf2cons cf

getDefinitions :: CF -> [String]
getDefinitions cf = [ f | FunDef f _ _ <- cfgPragmas cf ]

prDummyTypes :: CF -> [String]
prDummyTypes cf = prDummyData : map prDummyType cats
  where
  cats = getTreeCats cf
  prDummyData
    | null cats = "data Tag"
    | otherwise = "data Tag =" +++ intercalate " | " (map mkRealType cats)
  prDummyType cat = "type" +++ cat +++ "= Tree" +++ mkRealType cat

mkRealType :: String -> String
mkRealType cat = cat ++ "_" -- FIXME: make sure that there is no such category already

prTreeType :: TokenText -> CF -> [String]
prTreeType tokenText cf =
  "data Tree :: Tag -> * where" : map (("    " ++) . prTreeCons) (cf2cons cf)
  where
  prTreeCons c
      | TokenCat tok <- cat, isPositionCat cf tok =
          fun +++ ":: ((Int,Int),"++ tokenTextType tokenText ++") -> Tree" +++ mkRealType tok
      | otherwise =
          fun +++ "::" +++ concat [show c +++ "-> " | (c,_) <- consVars c] ++ "Tree" +++ mkRealType (show cat)
    where
    (cat,fun) = (consCat c, consFun c)

prCompos :: CF -> [String]
prCompos cf =
    ["instance Compos Tree where",
     "  compos r a f t = case t of"]
    ++ map ("      "++) (concatMap prComposCons cs
                         ++ ["_ -> r t" | not (all isRecursive cs)])
  where
    cs = cf2cons cf
    prComposCons c
        | isRecursive c = [consFun c +++ unwords (map snd (consVars c)) +++ "->" +++ rhs c]
        | otherwise = []
    isRecursive c = any (isTreeType cf) (map fst (consVars c))
    rhs c = "r" +++ consFun c +++ unwords (map prRec (consVars c))
      where prRec (cat,var) | not (isTreeType cf cat) = "`a`" +++ "r" +++ var
                            | isList cat = "`a` P.foldr (\\ x z -> r (:) `a` f x `a` z) (r [])" +++ var
                            | otherwise = "`a`" +++ "f" +++ var

prShow :: CF -> [String]
prShow cf = ["instance P.Show (Tree c) where",
              "  showsPrec n t = case t of"]
              ++ map (("    "++) .prShowCons) cs
              ++ ["   where opar n = if n > 0 then P.showChar '(' else P.id",
                  "         cpar n = if n > 0 then P.showChar ')' else P.id"]
  where
    cs = cf2cons cf
    prShowCons c | null vars = fun +++ "->" +++ "P.showString" +++ show fun
                 | otherwise = fun +++ unwords (map snd vars) +++ "->"
                                   +++ "opar n . P.showString" +++ show fun
                                   +++ unwords [". P.showChar ' ' . P.showsPrec 1 " ++ x | (_,x) <- vars]
                                   +++ ". cpar n"
      where (fun, vars) = (consFun c, consVars c)

prEq :: CF -> [String]
prEq cf = ["instance P.Eq (Tree c) where (==) = johnMajorEq",
           "",
           "johnMajorEq :: Tree a -> Tree b -> P.Bool"]
           ++ map prEqCons (cf2cons cf)
           ++ ["johnMajorEq _ _ = P.False"]
  where prEqCons c
            | null vars = "johnMajorEq" +++ fun +++ fun +++ "=" +++ "P.True"
            | otherwise = "johnMajorEq" +++ "(" ++ fun +++ unwords vars ++ ")"
                          +++ "(" ++ fun +++ unwords vars' ++ ")" +++ "="
                          +++ intercalate " && " (zipWith (\x y -> x +++ "==" +++ y) vars vars')
          where (fun, vars) = (consFun c, map snd (consVars c))
                vars' = map (++ "_") vars

prOrd :: CF -> [String]
prOrd cf = concat
  [ [ "instance P.Ord (Tree c) where"
    , "  compare x y = P.compare (index x) (index y) `P.mappend` compareSame x y"
    ]
  , [ "", "index :: Tree c -> P.Int" ]
  , zipWith mkIndex cs [0..]
  , when (null cs) [ "index = P.undefined" ]
  , [ "", "compareSame :: Tree c -> Tree c -> P.Ordering" ]
  , map mkCompareSame cs
  , [ "compareSame x y = P.error \"BNFC error:\" compareSame" ]
  ]
  where cs = cf2cons cf
        mkCompareSame c
            | null vars = "compareSame" +++ fun +++ fun +++ "=" +++ "P.EQ"
            | otherwise = "compareSame" +++ "(" ++ fun +++ unwords vars ++ ")"
                          +++ "(" ++ fun +++ unwords vars' ++ ")" +++ "="
                          +++ foldr1 (\x y -> "P.mappend (" ++ x ++") ("++y++")") cc
            where (fun, vars) = (consFun c, map snd (consVars c))
                  vars' = map (++"_") vars
                  cc = zipWith (\x y -> "P.compare"+++x+++y) vars vars'
        mkIndex c i = "index" +++ "(" ++ consFun c
                       +++ unwords (replicate (length (consVars c)) "_") ++ ")"
                       +++ "=" +++ show i
