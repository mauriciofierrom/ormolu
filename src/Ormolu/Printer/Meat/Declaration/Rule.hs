{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

module Ormolu.Printer.Meat.Declaration.Rule
  ( p_ruleDecls
  )
where

import BasicTypes
import Control.Monad
import FastString (unpackFS)
import GHC
import Ormolu.Printer.Combinators
import Ormolu.Printer.Meat.Common
import Ormolu.Printer.Meat.Declaration.Signature
import Ormolu.Printer.Meat.Declaration.Value
import Ormolu.Utils
import qualified Data.List.NonEmpty as NE
import qualified Data.Text as T

p_ruleDecls :: RuleDecls GhcPs -> R ()
p_ruleDecls = \case
  HsRules NoExt _ xs -> line $ pragma "RULES" $
    velt' $ (located' p_ruleDecl) <$> xs
  XRuleDecls NoExt -> notImplemented "XRuleDecls"

p_ruleDecl :: RuleDecl GhcPs -> R ()
p_ruleDecl = \case
  HsRule NoExt ruleName activation ruleBndrs lhs rhs -> do
    located ruleName p_ruleName
    let gotBinders = not (null ruleBndrs)
    when (visibleActivation activation || gotBinders) space
    p_activation activation
    when (visibleActivation activation && gotBinders) space
    p_ruleBndrs ruleBndrs
    breakpoint
    inci $ do
      located lhs p_hsExpr
      txt " ="
      inci $ do
        breakpoint
        located rhs p_hsExpr
  XRuleDecl NoExt -> notImplemented "XRuleDecl"

p_ruleName :: (SourceText, RuleName) -> R ()
p_ruleName (_, name) = do
  txt "\""
  txt $ T.pack $ unpackFS $ name
  txt "\""

p_ruleBndrs :: [LRuleBndr GhcPs] -> R ()
p_ruleBndrs bndrs =
  forM_ (NE.nonEmpty bndrs) $ \bndrs_ne ->
    switchLayout (combineSrcSpans' (getLoc <$> bndrs_ne)) $ do
      txt "forall"
      breakpoint
      inci $ do
        velt' (located' p_ruleBndr <$> bndrs)
        txt "."

p_ruleBndr :: RuleBndr GhcPs -> R ()
p_ruleBndr = \case
  RuleBndr NoExt x -> p_rdrName x
  RuleBndrSig NoExt x hswc -> parens $ do
    p_rdrName x
    p_typeAscription hswc
  XRuleBndr NoExt -> notImplemented "XRuleBndr"
