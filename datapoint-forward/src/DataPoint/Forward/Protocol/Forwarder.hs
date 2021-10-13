{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE NamedFieldPuns #-}

module DataPoint.Forward.Protocol.Forwarder
  ( DataPointForwarder (..)
  , traceForwarderPeer
  ) where

import           Data.Text (Text)

import           Network.TypedProtocol.Core (Peer (..), PeerHasAgency (..),
                                             PeerRole (..))

import           DataPoint.Forward.Protocol.Type

data DataPointForwarder lo m a = DataPointForwarder
  { -- | The acceptor sent us a request for new 'TraceObject's.
    recvMsgTraceObjectsRequest
      :: [Text]
      -> m ([lo], DataPointForwarder lo m a)

    -- | The acceptor terminated. Here we have a pure return value, but we
    -- could have done another action in 'm' if we wanted to.
  , recvMsgDone :: m a
  }

-- | Interpret a particular action sequence into the server side of the protocol.
--
traceForwarderPeer
  :: Monad m
  => DataPointForwarder lo m a
  -> Peer (DataPointForward lo) 'AsServer 'StIdle m a
traceForwarderPeer DataPointForwarder{recvMsgTraceObjectsRequest, recvMsgDone} =
  -- In the 'StIdle' state the forwarder is awaiting a request message
  -- from the acceptor.
  Await (ClientAgency TokIdle) $ \case
    -- The acceptor sent us a request for new 'TraceObject's, so now we're
    -- in the 'StBusy' state which means it's the forwarder's turn to send
    -- a reply.
    MsgTraceObjectsRequest request -> Effect $ do
      (reply, next) <- recvMsgTraceObjectsRequest request
      return $ Yield (ServerAgency TokBusy)
                     (MsgTraceObjectsReply reply)
                     (traceForwarderPeer next)

    -- The acceptor sent the done transition, so we're in the 'StDone' state
    -- so all we can do is stop using 'done', with a return value.
    MsgDone -> Effect $ Done TokDone <$> recvMsgDone
