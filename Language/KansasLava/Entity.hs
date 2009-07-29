module Language.KansasLava.Entity where

import qualified Data.Traversable as T
import qualified Data.Foldable as F
import Control.Applicative
import Data.Unique
import Data.Monoid
  
data Name = Name String String
    deriving (Eq, Ord)

instance Show Name where
    show (Name "" nm)  = nm
    show (Name pre nm) =  pre ++ "::" ++ nm

name :: String -> Name
name n  = Name "" n

data Var = Var String
         | NoVar                -- not needed, because the default does fine???
    deriving (Eq,Ord)

instance Show Var where
    show (Var nm)  = nm
{-
-- The old defintion.
data Entity s = Entity Name [(Var,s)]      -- an entity
              | Port Var s                 -- projection; get a specific named port of an entity
              | Pad Var                    -- some in-scope signal
              | Lit Integer
              deriving (Show, Eq, Ord)
-}             
-- you want to tie the knot at the 'Entity' level, for observable sharing.

data Entity s = Entity Name [Var] [(Var,Driver s)]
              deriving (Show, Eq, Ord)
             
             
-- These can all be unshared without any problems.
data Driver s = Port Var s      -- a specific port on the entity
              | Pad Var         -- 
              | Lit Integer
              deriving (Show, Eq, Ord)

instance T.Traversable Entity where
  traverse f (Entity v vs ss) = Entity v vs <$> T.traverse (\ (v,a) -> ((,) v) `fmap` T.traverse f a) ss

instance T.Traversable Driver where
  traverse f (Port v s)    = Port v <$> f s
  traverse _ (Pad v)       = pure $ Pad v
  traverse _ (Lit i)       = pure $ Lit i
  
instance F.Foldable Entity where
  foldMap f (Entity v vs ss) = mconcat [ F.foldMap f d | (_,d) <- ss ]
  
instance F.Foldable Driver where
  foldMap f (Port v s)    = f s
  foldMap _ (Pad v)       = mempty
  foldMap _ (Lit i)       = mempty

instance Functor Entity where
    fmap f (Entity v vs ss) = Entity v vs (fmap (\ (v,a) -> (v,fmap f a)) ss)
    
instance Functor Driver where
    fmap f (Port v s)    = Port v (f s)
    fmap _ (Pad v)       = Pad v
    fmap _ (Lit i)       = Lit i
