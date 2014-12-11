{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ConstraintKinds #-}
{- |
Module      :  Control.SIArrow
Description :  Categories of reversible computations.
Copyright   :  (c) Paweł Nowak
License     :  MIT

Maintainer  :  Paweł Nowak <pawel834@gmail.com>
Stability   :  experimental

Categories of reversible computations.
-}
module Control.SIArrow (
    -- * Arrow.
    SIArrow(..),
    (^>>), (>>^), (^<<), (<<^),

    -- * Functor and applicative.
    (/$/), (/$~),
    (/*/), (/*), (*/),

    -- * Signaling errors.
    sifail, (/?/),

    -- * Combinators.
    sisequence,
    sisequence_,
    sireplicate,
    sireplicate_
    ) where

import           Control.Arrow (Kleisli(..))
import           Control.Category
import           Control.Category.Structures
import           Control.Lens.Cons
import           Control.Lens.Empty
import           Control.Lens.SemiIso
import           Control.Monad
import           Data.Tuple.Morph
import           Prelude hiding (id, (.))

infixr 1 ^>>, >>^
infixr 1 ^<<, <<^
infixl 4 /$/, /$~
infixl 5 /*/, */, /*
infixl 3 /?/

-- | A category equipped with an embedding 'siarr' from @SemiIso@ into @cat@ and some
-- additional structure.
--
-- SIArrow abstracts categories of reversible computations
-- (with reversible side effects).
--
-- The category @cat@ should contain @SemiIso@ as a sort of
-- \"subcategory of pure computations\".
class (Products cat, Coproducts cat, CatPlus cat) => SIArrow cat where
    -- | Allows you to lift a SemiIso into @cat@. The resulting arrow should be
    -- in some sense minimal or \"pure\", similiar to 'pure', 'return' and
    -- 'arr' from "Control.Category".
    siarr :: ASemiIso' a b -> cat a b

    -- | Reversed version of 'siarr'.
    --
    -- Use this where you would use 'pure'.
    sipure :: ASemiIso' b a -> cat a b
    sipure = siarr . rev

    -- | @sisome v@ repeats @v@ as long as possible, but no less then once.
    sisome :: cat () b -> cat () [b]
    sisome v = _Cons /$/ v /*/ simany v

    -- | @simany v@ repeats @v@ as long as possible.
    simany :: cat () b -> cat () [b]
    simany v = sisome v /+/ sipure _Empty

    {-# MINIMAL siarr #-}

instance MonadPlus m => SIArrow (Kleisli m) where
    siarr ai = Kleisli $ either fail return . apply ai

instance SIArrow ReifiedSemiIso' where
    siarr = reifySemiIso

-- | Composes a SemiIso with an arrow.
(^>>) :: SIArrow cat => ASemiIso' a b -> cat b c -> cat a c
f ^>> a = a . siarr f

-- | Composes an arrow with a SemiIso.
(>>^) :: SIArrow cat => cat a b -> ASemiIso' b c -> cat a c
a >>^ f = siarr f . a

-- | Composes a SemiIso with an arrow, backwards.
(^<<) :: SIArrow cat => ASemiIso' b c -> cat a b -> cat a c
f ^<< a = siarr f . a

-- | Composes an arrow with a SemiIso, backwards.
(<<^) :: SIArrow cat => cat b c -> ASemiIso' a b -> cat a c
a <<^ f = a . siarr f

-- | Postcomposes an arrow with a reversed SemiIso. The analogue of '<$>'.
(/$/) :: SIArrow cat => ASemiIso' b' b -> cat a b -> cat a b'
ai /$/ f = sipure ai . f

-- | Convenient fmap.
--
-- > ai /$~ f = ai . morphed /$/ f
--
-- This operator handles all the hairy stuff with uncurried application:
-- it reassociates the argument tuple and removes unnecessary (or adds necessary)
-- units to match the function type. You don't have to use @/*@ and @*/@ with this
-- operator.
(/$~) :: (SIArrow cat, HFoldable b', HFoldable b,
           HUnfoldable b', HUnfoldable b, Rep b' ~ Rep b)
       => ASemiIso' a b' -> cat c b -> cat c a
ai /$~ h = cloneSemiIso ai . morphed /$/ h

-- | The product of two arrows with duplicate units removed. Side effect are
-- sequenced from left to right.
--
-- The uncurried analogue of '<*>'.
(/*/) :: SIArrow cat => cat () b -> cat () c -> cat () (b, c)
a /*/ b = unit ^>> (a *** b)

-- | The product of two arrows, where the second one has no input and no output
-- (but can have side effects), with duplicate units removed. Side effect are
-- sequenced from left to right.
--
-- The uncurried analogue of '<*'.
(/*)  :: SIArrow cat => cat () a -> cat () () -> cat () a
f /* g = unit /$/ f /*/ g

-- | The product of two arrows, where the first one has no input and no output
-- (but can have side effects), with duplicate units removed. Side effect are
-- sequenced from left to right.
--
-- The uncurried analogue of '*>'.
(*/)  :: SIArrow cat => cat () () -> cat () a -> cat () a
f */ g = unit . swapped /$/ f /*/ g

-- | An arrow that fails with an error message.
sifail :: SIArrow cat => String -> cat a b
sifail = siarr . alwaysFailing

-- | Provides an error message in the case of failure.
(/?/) :: SIArrow cat => cat a b -> String -> cat a b
f /?/ msg = f /+/ sifail msg

-- | Equivalent of 'sequence'.
sisequence :: SIArrow cat => [cat () a] -> cat () [a]
sisequence [] = sipure _Empty
sisequence (x:xs) = _Cons /$/ x /*/ sisequence xs

-- | Equivalent of 'sequence_', restricted to units.
sisequence_ :: SIArrow cat => [cat () ()] -> cat () ()
sisequence_ [] = sipure _Empty
sisequence_ (x:xs) = unit /$/ x /*/ sisequence_ xs

-- | Equivalent of 'replicateM'.
sireplicate :: SIArrow cat => Int -> cat () a -> cat () [a]
sireplicate n f = sisequence (replicate n f)

-- | Equivalent of 'replicateM_', restricted to units.
sireplicate_ :: SIArrow cat => Int -> cat () () -> cat () ()
sireplicate_ n f = sisequence_ (replicate n f)