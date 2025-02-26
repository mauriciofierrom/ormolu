{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

-- | Rendering of type class declarations.

module Ormolu.Printer.Meat.Declaration.Class
  ( p_classDecl
  )
where

import Class
import Control.Arrow
import Control.Monad
import Data.Foldable
import Data.List (sortBy)
import Data.Ord (comparing)
import GHC
import Ormolu.Printer.Combinators
import Ormolu.Printer.Meat.Common
import Ormolu.Printer.Meat.Type
import Ormolu.Utils
import RdrName (RdrName (..))
import SrcLoc (Located, combineSrcSpans)
import {-# SOURCE #-} Ormolu.Printer.Meat.Declaration

p_classDecl
  :: LHsContext GhcPs
  -> Located RdrName
  -> LHsQTyVars GhcPs
  -> LexicalFixity
  -> [Located (FunDep (Located RdrName))]
  -> [LSig GhcPs]
  -> LHsBinds GhcPs
  -> [LFamilyDecl GhcPs]
  -> [LTyFamDefltEqn GhcPs]
  -> R ()
p_classDecl ctx name tvars fixity fdeps csigs cdefs cats catdefs = do
  let HsQTvs {..} = tvars
      variableSpans = foldr (combineSrcSpans . getLoc) noSrcSpan hsq_explicit
      signatureSpans = getLoc name `combineSrcSpans` variableSpans
      dependencySpans = foldr (combineSrcSpans . getLoc) noSrcSpan fdeps
      combinedSpans =
        getLoc ctx `combineSrcSpans`
        signatureSpans `combineSrcSpans`
        dependencySpans
  txt "class"
  switchLayout combinedSpans $ do
    breakpoint
    inci $ do
      p_classContext ctx
      switchLayout signatureSpans $ do
        p_infixDefHelper
          (isInfix fixity)
          inci
          (p_rdrName name)
          (located' p_hsTyVarBndr <$> hsq_explicit)
      inci (p_classFundeps fdeps)
  -- GHC's AST does not necessarily store each kind of element in source
  -- location order. This happens because different declarations are stored in
  -- different lists. Consequently, to get all the declarations in proper order,
  -- they need to be manually sorted.
  let sigs = (getLoc &&& fmap (SigD NoExt)) <$> csigs
      vals = (getLoc &&& fmap (ValD NoExt)) <$> toList cdefs
      tyFams = (getLoc &&& fmap (TyClD NoExt . FamDecl NoExt)) <$> cats
      tyFamDefs =
        ( getLoc &&& fmap (InstD NoExt . TyFamInstD NoExt . defltEqnToInstDecl)
        ) <$> catdefs
      allDecls =
        snd <$> sortBy (comparing fst) (sigs <> vals <> tyFams <> tyFamDefs)
  if not (null allDecls)
  then do
    txt " where"
    newline -- Ensure line is added after where clause.
    newline -- Add newline before first declaration.
    inci (p_hsDecls Associated allDecls)
  else newline

p_classContext :: LHsContext GhcPs -> R ()
p_classContext ctx = unless (null (unLoc ctx)) $ do
  located ctx p_hsContext
  breakpoint
  txt "=> "

p_classFundeps :: [Located (FunDep (Located RdrName))] -> R ()
p_classFundeps fdeps = unless (null fdeps) $ do
  breakpoint
  txt "| "
  velt $ withSep comma (located' p_funDep) fdeps

p_funDep :: FunDep (Located RdrName) -> R ()
p_funDep (before, after) = do
  spaceSep p_rdrName before
  txt " -> "
  spaceSep p_rdrName after

----------------------------------------------------------------------------
-- Helpers

defltEqnToInstDecl :: TyFamDefltEqn GhcPs -> TyFamInstDecl GhcPs
defltEqnToInstDecl FamEqn {..} = TyFamInstDecl {..}
  where
    eqn = FamEqn {feqn_pats = tyVarsToTypes feqn_pats, ..}
    tfid_eqn = HsIB {hsib_ext = NoExt, hsib_body = eqn}
defltEqnToInstDecl XFamEqn {} = notImplemented "XFamEqn"

isInfix :: LexicalFixity -> Bool
isInfix = \case
  Infix -> True
  Prefix -> False
