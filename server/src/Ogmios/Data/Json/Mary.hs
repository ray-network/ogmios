--  This Source Code Form is subject to the terms of the Mozilla Public
--  License, v. 2.0. If a copy of the MPL was not distributed with this
--  file, You can obtain one at http://mozilla.org/MPL/2.0/.

{-# LANGUAGE TypeApplications #-}

module Ogmios.Data.Json.Mary where

import Ogmios.Data.Json.Prelude

import Cardano.Binary
    ( serialize'
    )
import Cardano.Ledger.Crypto
    ( Crypto
    )
import Cardano.Ledger.Val
    ( isZero
    )
import Data.ByteString.Base16
    ( encodeBase16
    )
import GHC.Records
    ( getField
    )
import Ouroboros.Consensus.Cardano.Block
    ( MaryEra
    )
import Ouroboros.Consensus.Protocol.TPraos
    ( TPraos
    )
import Ouroboros.Consensus.Shelley.Ledger.Block
    ( ShelleyBlock (..)
    )
import Ouroboros.Consensus.Shelley.Protocol.TPraos
    ()

import qualified Data.ByteString.Short as BS
import qualified Data.Map.Strict as Map

import qualified Ogmios.Data.Json.Allegra as Allegra
import qualified Ogmios.Data.Json.Shelley as Shelley

import qualified Cardano.Ledger.Block as Ledger
import qualified Cardano.Ledger.Core as Ledger
import qualified Cardano.Ledger.Era as Ledger
import qualified Cardano.Ledger.TxIn as Ledger

import qualified Cardano.Ledger.Shelley.BlockChain as Sh
import qualified Cardano.Ledger.Shelley.PParams as Sh
import qualified Cardano.Ledger.Shelley.Rules.Ledger as Sh
import qualified Cardano.Ledger.Shelley.Tx as Sh
import qualified Cardano.Ledger.Shelley.TxBody as Sh
import qualified Cardano.Ledger.Shelley.UTxO as Sh

import qualified Cardano.Ledger.AuxiliaryData as MA
import qualified Cardano.Ledger.Mary.Value as MA
import qualified Cardano.Ledger.ShelleyMA.AuxiliaryData as MA
import qualified Cardano.Ledger.ShelleyMA.Rules.Utxo as MA
import qualified Cardano.Ledger.ShelleyMA.TxBody as MA

--
-- Encoders
--

encodeAuxiliaryData
    :: Crypto crypto
    => MA.AuxiliaryData (MaryEra crypto)
    -> Json
encodeAuxiliaryData (MA.AuxiliaryData blob scripts) =
    "blob" .=
        Shelley.encodeMetadataBlob blob <>
    "scripts" .=
        encodeFoldable Allegra.encodeScript scripts
    & encodeObject

encodeBlock
    :: Crypto crypto
    => ShelleyBlock (TPraos crypto) (MaryEra crypto)
    -> Json
encodeBlock (ShelleyBlock (Ledger.Block blkHeader txs) headerHash) =
    "body" .=
        encodeFoldable encodeTx (Sh.txSeqTxns' txs) <>
    "header" .=
        Shelley.encodeBHeader blkHeader <>
    "headerHash" .=
        Shelley.encodeShelleyHash headerHash
    & encodeObject

encodeLedgerFailure
    :: Crypto crypto
    => Sh.LedgerPredicateFailure (MaryEra crypto)
    -> Json
encodeLedgerFailure = \case
    Sh.UtxowFailure e  ->
        Shelley.encodeUtxowFailure encodeUtxoFailure e
    Sh.DelegsFailure e ->
        Shelley.encodeDelegsFailure e

encodePolicyId
    :: Crypto crypto
    => MA.PolicyID crypto
    -> Json
encodePolicyId (MA.PolicyID hash) =
    Shelley.encodeScriptHash hash

encodePParams'
    :: (forall a. Text -> (a -> Json) -> Sh.HKD f a -> Series)
    -> Sh.PParams' f era
    -> Json
encodePParams' =
    Shelley.encodePParams'

encodeProposedPPUpdates
    :: Ledger.PParamsDelta era ~ Sh.PParamsUpdate era
    => Crypto (Ledger.Crypto era)
    => Sh.ProposedPPUpdates era
    -> Json
encodeProposedPPUpdates =
    Shelley.encodeProposedPPUpdates

encodeTx
    :: forall crypto. (Crypto crypto)
    => Sh.Tx (MaryEra crypto)
    -> Json
encodeTx x =
    "id" .=
        Shelley.encodeTxId (Ledger.txid @(MaryEra crypto) (Sh.body x)) <>
    "body" .=
        encodeTxBody (Sh.body x) <>
    "metadata" .=? OmitWhenNothing
        identity metadata <>
    "witness" .=
        encodeWitnessSet (Sh.wits x) <>
    "raw" .=
        encodeByteStringBase16 (serialize' x)
    & encodeObject
  where
    adHash :: MA.TxBody era -> StrictMaybe (MA.AuxiliaryDataHash (Ledger.Crypto era))
    adHash = getField @"adHash"

    metadata = liftA2
        (\hash body -> encodeObject ("hash" .= hash <> "body" .= body))
        (Shelley.encodeAuxiliaryDataHash <$> adHash (Sh.body x))
        (encodeAuxiliaryData <$> Sh.auxiliaryData x)

encodeTxBody
    :: Crypto crypto
    => MA.TxBody (MaryEra crypto)
    -> Json
encodeTxBody (MA.TxBody inps outs certs wdrls fee validity updates _ mint) =
    "inputs" .=
        encodeFoldable Shelley.encodeTxIn inps <>
    "outputs" .=
        encodeFoldable encodeTxOut outs <>
    "withdrawals" .=? OmitWhen (null . Sh.unWdrl)
        Shelley.encodeWdrl wdrls <>
    "certificates" .=? OmitWhen null
        (encodeFoldable Shelley.encodeDCert) certs <>
    "mint" .=? OmitWhen isZero
        encodeValue mint <>
    "fee" .=
        encodeCoin fee <>
    "validityInterval" .=
        Allegra.encodeValidityInterval validity <>
    "update" .=? OmitWhenNothing
        Shelley.encodeUpdate updates
    & encodeObject

encodeTxOut
    :: Crypto crypto
    => Sh.TxOut (MaryEra crypto)
    -> Json
encodeTxOut (Sh.TxOut addr value) =
    "address" .=
        Shelley.encodeAddress addr <>
    "value" .=
        encodeValue value
    & encodeObject

encodeUtxo
    :: Crypto crypto
    => Sh.UTxO (MaryEra crypto)
    -> Json
encodeUtxo =
    encodeList id . Map.foldrWithKey (\i o -> (:) (encodeIO i o)) [] . Sh.unUTxO
  where
    encodeIO = curry (encode2Tuple Shelley.encodeTxIn encodeTxOut)

encodeUtxoFailure
    :: Crypto crypto
    => MA.UtxoPredicateFailure (MaryEra crypto)
    -> Json
encodeUtxoFailure = \case
    MA.BadInputsUTxO inputs ->
        "badInputs" .=
            encodeFoldable Shelley.encodeTxIn inputs
        & encodeObject
    MA.OutsideValidityIntervalUTxO itv currentSlot ->
        "outsideOfValidityInterval" .= encodeObject
            ( "interval" .= Allegra.encodeValidityInterval itv <>
              "currentSlot" .= encodeSlotNo currentSlot
            )
        & encodeObject
    MA.OutputTooBigUTxO outs ->
        "tooManyAssetsInOutput" .=
            encodeFoldable encodeTxOut outs
        & encodeObject
    MA.MaxTxSizeUTxO actualSize maxSize ->
        "txTooLarge" .= encodeObject
            ( "maximumSize" .= encodeInteger maxSize <>
              "actualSize" .= encodeInteger actualSize
            )
        & encodeObject
    MA.InputSetEmptyUTxO ->
        "missingAtLeastOneInputUtxo" .=
            encodeNull
        & encodeObject
    MA.FeeTooSmallUTxO required actual ->
        "feeTooSmall" .= encodeObject
              ( "requiredFee" .= encodeCoin required <>
                "actualFee" .= encodeCoin actual
              )
        & encodeObject
    MA.ValueNotConservedUTxO consumed produced ->
        "valueNotConserved" .= encodeObject
            ( "consumed" .= encodeValue consumed <>
              "produced" .= encodeValue produced
            )
        & encodeObject
    MA.WrongNetwork expected invalidAddrs ->
        "networkMismatch" .= encodeObject
            ( "expectedNetwork" .=
                Shelley.encodeNetwork expected <>
              "invalidEntities" .=
                Shelley.encodeEntities "address" Shelley.encodeAddress invalidAddrs
            )
        & encodeObject
    MA.WrongNetworkWithdrawal expected invalidAccts ->
        "networkMismatch" .= encodeObject
            ( "expectedNetwork" .=
                Shelley.encodeNetwork expected <>
              "invalidEntities" .=
                Shelley.encodeEntities "rewardAccount" Shelley.encodeRewardAcnt invalidAccts
            )
        & encodeObject
    MA.OutputTooSmallUTxO outs ->
        "outputTooSmall" .=
            encodeFoldable encodeTxOut outs
        & encodeObject
    MA.OutputBootAddrAttrsTooBig outs ->
        "addressAttributesTooLarge" .=
            encodeFoldable Shelley.encodeAddress ((\(Sh.TxOut addr _) -> addr) <$> outs)
        & encodeObject
    MA.TriesToForgeADA ->
        "triesToForgeAda" .=
            encodeNull
        & encodeObject
    MA.UpdateFailure e ->
        Shelley.encodeUpdateFailure e

encodeValue
    :: Crypto crypto
    => MA.Value crypto
    -> Json
encodeValue (MA.Value coins assets) =
    "coins" .=
        encodeInteger coins <>
    "assets" .=
        encodeMap stringifyAssetId encodeInteger (flatten assets)
    & encodeObject
  where
    flatten :: (Ord k1, Ord k2) => Map k1 (Map k2 a) -> Map (k1, k2) a
    flatten = Map.foldrWithKey
        (\k inner -> Map.union (Map.mapKeys (k,) inner))
        mempty

encodeWitnessSet
    :: Crypto crypto
    => Sh.WitnessSet (MaryEra crypto)
    -> Json
encodeWitnessSet x =
    "signatures" .=
        Shelley.encodeWitVKeys (Sh.addrWits x) <>
    "scripts" .=
        encodeMap Shelley.stringifyScriptHash Allegra.encodeScript (Sh.scriptWits x) <>
    "bootstrap" .=
        encodeFoldable Shelley.encodeBootstrapWitness (Sh.bootWits x)
    & encodeObject

--
-- Conversion To Text
--

stringifyAssetId :: Crypto crypto => (MA.PolicyID crypto, MA.AssetName) -> Text
stringifyAssetId (MA.PolicyID pid, MA.AssetName bytes)
    | BS.null bytes = Shelley.stringifyScriptHash pid
    | otherwise     = Shelley.stringifyScriptHash pid <> "." <> encodeBase16 (fromShort bytes)
