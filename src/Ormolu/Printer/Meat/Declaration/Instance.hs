{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards   #-}

-- | Type class, type family, and data family instance declarations.

module Ormolu.Printer.Meat.Declaration.Instance
  ( p_clsInstDecl
  , p_tyFamInstDecl
  , p_dataFamInstDecl
  , p_standaloneDerivDecl
  )
where

import BasicTypes
import Control.Arrow
import Data.Foldable
import Data.List (sortBy)
import Data.Ord (comparing)
import GHC
import Ormolu.Printer.Combinators
import Ormolu.Printer.Meat.Common
import Ormolu.Printer.Meat.Declaration.Data
import Ormolu.Printer.Meat.Declaration.TypeFamily
import Ormolu.Printer.Meat.Type
import Ormolu.Utils
import {-# SOURCE #-} Ormolu.Printer.Meat.Declaration

p_standaloneDerivDecl :: DerivDecl GhcPs -> R ()
p_standaloneDerivDecl DerivDecl {..} = do
  let typesAfterInstance = located (hsib_body (hswc_body deriv_type)) p_hsType
      instTypes toIndent = inci $ do
        txt "instance"
        breakpoint
        match_overlap_mode deriv_overlap_mode breakpoint
        if toIndent
          then inci typesAfterInstance
          else typesAfterInstance
  txt "deriving"
  case deriv_strategy of
    Nothing -> do
      space
      instTypes False
    Just l -> locatedVia Nothing l $ \case
      StockStrategy -> do
        txt " stock "
        instTypes False
      AnyclassStrategy -> do
        txt " anyclass "
        instTypes False
      NewtypeStrategy -> do
        txt " newtype "
        instTypes False
      ViaStrategy HsIB {..} -> do
        txt " via"
        breakpoint
        inci (located hsib_body p_hsType)
        breakpoint
        instTypes True
      ViaStrategy (XHsImplicitBndrs NoExt) ->
        notImplemented "XHsImplicitBndrs"
  newline
p_standaloneDerivDecl (XDerivDecl _) = notImplemented "XDerivDecl"

p_clsInstDecl :: ClsInstDecl GhcPs -> R ()
p_clsInstDecl = \case
  ClsInstDecl {..} -> do
    txt "instance"
    case cid_poly_ty of
      HsIB {..} -> located hsib_body $ \x -> do
        breakpoint
        inci $ do
          match_overlap_mode cid_overlap_mode breakpoint
          p_hsType x
      XHsImplicitBndrs NoExt -> notImplemented "XHsImplicitBndrs"
    -- GHC's AST does not necessarily store each kind of element in source
    -- location order. This happens because different declarations are stored in
    -- different lists. Consequently, to get all the declarations in proper
    -- order, they need to be manually sorted.
    let sigs = (getLoc &&& fmap (SigD NoExt)) <$> cid_sigs
        vals = (getLoc &&& fmap (ValD NoExt)) <$> toList cid_binds
        tyFamInsts =
          ( getLoc &&& fmap (InstD NoExt . TyFamInstD NoExt)
          ) <$> cid_tyfam_insts
        dataFamInsts =
          ( getLoc &&& fmap (InstD NoExt . DataFamInstD NoExt)
          ) <$> cid_datafam_insts
        allDecls =
          snd <$>
            sortBy (comparing fst) (sigs <> vals <> tyFamInsts <> dataFamInsts)
    if not (null allDecls)
    then do
      txt " where"
      newline -- Ensure line is added after where clause.
      newline -- Add newline before first declaration.
      inci (p_hsDecls Associated allDecls)
    else newline
  XClsInstDecl NoExt -> notImplemented "XClsInstDecl"

p_tyFamInstDecl :: FamilyStyle -> TyFamInstDecl GhcPs -> R ()
p_tyFamInstDecl style = \case
  TyFamInstDecl {..} -> do
    txt $ case style of
      Associated -> "type"
      Free -> "type instance"
    breakpoint
    inci (p_tyFamInstEqn tfid_eqn)
    newline

p_dataFamInstDecl :: FamilyStyle -> DataFamInstDecl GhcPs -> R ()
p_dataFamInstDecl style = \case
  DataFamInstDecl {..} -> do
    let HsIB {..} = dfid_eqn
        FamEqn {..} = hsib_body
    p_dataDecl style feqn_tycon feqn_pats feqn_fixity feqn_rhs

match_overlap_mode :: Maybe (Located OverlapMode) -> R () -> R ()
match_overlap_mode overlap_mode layoutStrategy =
  case unLoc <$> overlap_mode of
    Just Overlappable {} -> do
      txt "{-# OVERLAPPABLE #-}"
      layoutStrategy
    Just Overlapping {} -> do
      txt "{-# OVERLAPPING #-}"
      layoutStrategy
    Just Overlaps {} -> do
      txt "{-# OVERLAPS #-}"
      layoutStrategy
    Just Incoherent {} -> do
      txt "{-# INCOHERENT #-}"
      layoutStrategy
    _ -> pure ()
