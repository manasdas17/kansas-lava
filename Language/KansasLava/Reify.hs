{-# LANGUAGE TypeFamilies, FlexibleInstances,ParallelListComp #-}
module Language.KansasLava.Reify where

import Data.Reify
import Data.List as L


import Language.KansasLava.Entity
import Language.KansasLava.Signal
import Language.KansasLava.Type
import Language.KansasLava.Sequential(Time(..))

--------------------------------------------------------
-- Grab a set of drivers (the outputs), and give me a graph, please.

data Uq = Uq Unique | Sink | Source
	deriving (Eq,Ord,Show)

data ReifiedCircuit = ReifiedCircuit
	{ theCircuit :: [(Unique,Entity BaseTy Unique)]
		-- ^ This the main graph. There is no actual node for the source or sink.
	, theSrcs    :: [(Var,BaseTy)]
	, theSinks   :: [(Var,BaseTy,Driver Unique)]
	-- , theTypes   :: TypeEnv
	}


data ReifyOptions
	= InputNames [String]
	| OutputNames [String]
	| DebugReify		-- show debugging output of the reification stage
	deriving (Eq, Show)


-- | reifyCircuit does reification and type inference.
-- reifyCircuit :: REIFY circuit => [ReifyOptions] -> circuit -> IO ReifiedCircuit
-- ([(Unique,Entity (Ty Var) Unique)],[(Var,Driver Unique)])
reifyCircuit :: (Ports a) => [ReifyOptions] -> a -> IO ReifiedCircuit

reifyCircuit opts circuit = do
        -- GenSym for input/output pad names
	let inputNames = head $
		[ nms | InputNames nms <- opts ] ++ [[ "i" ++ show i | i <- [0..]]]
	let outputNames = head $
		[ nms | OutputNames nms <- opts ] ++ [[ "o" ++ show i | i <- [0..]]]


        let (ty,o) = ports inputNames circuit


        -- Get the graph, and associate the output drivers for the graph with
        -- output pad names.
        (gr, outputs) <- case o of
                Port _ o' -> do
                   (Graph gr out) <- reifyGraph o'
                   case lookup out gr of
                     Just (Entity (Name "Lava" "top")  _ ins _) ->
                       return $ (gr,[(Var sink,ity, driver)
                                       | (_,ity,driver) <- ins
                                       | sink <- outputNames])
                     Just (Entity (Name _ _) outs _ _) ->
                       return $ (gr, [(Var sink,oty, Port ovar out)
                                      | (ovar,oty) <- outs
                                      | sink <- outputNames])
		     Just (Table (ovar,oty) _ _) ->
		       return $ (gr, [ (Var sink,oty, Port ovar out)
                                     | sink <- [head outputNames]
				     ])
                     _ -> error $ "reifyCircuit: " ++ show o




                (Lit x) -> return ([],[(Var (head outputNames),ty,Lit x)])
                v -> fail $ "reifyGraph failed in reifyCircuit" ++ show v

        -- Search all of the enities, looking for input ports.
        let inputs = [ (v,vTy) | (_,Entity _ _ ins _) <- gr, (_,vTy,Pad v) <- ins]
		  ++ [ (v,vTy) | (_,Table _ (_,vTy,Pad v) _) <- gr ]
        return $ ReifiedCircuit { theCircuit = gr
                                , theSrcs = nub inputs
                                , theSinks = outputs
                                }
-- Some more type class magic.
{-
entity ::
	(INPUT a, REIFY a,INPUT b) =>
{- REIFY circuit => -} [ReifyOptions]
	->  String -> (a -> b)  ->  (a -> b)
entity opts nm circuit  = circuit'
    where
	p_root = P []

	-- (a -> b) -> (a -> b)
	circuit' inpX = result -- {- o0 $ e_entity -}
	   where
		(result,pinsY) = generated' e_entity (P [1,2])
		e_entity =
        	    E
        	  $ Entity (Name "#AUTO" "ABC")
			 [ Var (show ps)
			 | (_,ps) <- pinsY
			 ]
			 [ (Var ("i" ++ show n),dr)
			 | (n,(ty,dr)) <- zip [0..] pinsX
			 ]
			 ([ [fmap undefined ty,TyVar v] | (ty,Port v _) <- pinsX ] ++
			  [ [fmap undefined ty,TyVar (Var $ show ps)] | (ty,ps) <- pinsY ])
		(insX,pinsX) = capture' p_root inpX
-}
{-
entity :: (REIFY b, CLONE b) => [ReifyOptions] ->String -> b -> b
entity opts nm circuit = clone circuit deep
  where
	deep = wrapCircuit [] [] circuit
-}


showReifiedCircuit :: (Ports circuit) => [ReifyOptions] -> circuit -> IO String
showReifiedCircuit opt c = do
	rCir <- reifyCircuit opt c
	let bar = (replicate 78 '-') ++ "\n"
        let showDriver :: Driver Unique -> BaseTy -> String
            showDriver (Port v i) ty = show i ++ "." ++ show v ++ ":" ++ show ty
            showDriver (Lit x) ty = show x ++ ":" ++ show ty
            showDriver (Pad x) ty = show x ++ ":" ++ show ty
            showDriver l _ = error $ "showDriver" ++ show l
	let inputs = unlines
		[ show var ++ " : " ++ show ty
		| (var,ty) <- theSrcs rCir
		]
	let outputs = unlines
		[ show var   ++ " <- " ++ showDriver dr ty
		| (var,ty,dr) <- theSinks rCir
		]
	let circuit = unlines
		[ case e of
		    Entity nm outs ins _	 ->
			"(" ++ show uq ++ ") " ++ show nm ++ "\n"
			    ++ unlines [ "      out " ++ show v ++ ":" ++ show ty | (v,ty) <- outs ]
 			    ++ unlines [ "      in  " ++ show v ++ " <- " ++ showDriver dr ty | (v,ty,dr) <- ins ]
		    Table (v0,ty0) (v1,ty1,dr) mapping ->
			"(" ++ show uq ++ ") TABLE \n" 
			    ++ "      out " ++ show v0 ++ ":" ++ show ty0 ++ "\n"
			    ++ "      in  " ++ show v1 ++ " <- " ++ showDriver dr ty1 ++ "\n"
			    ++ unlines [ "      case " ++ e1 ++ " -> " ++ e2 
				       | (i,e1,o,e2) <- mapping 
				       ]
		| (uq,e) <- theCircuit rCir
		]

	let msg = bar
		++ "-- Inputs                                                                   --\n"
		++ bar
		++ inputs
		++ bar
		++ "-- Outputs                                                                  --\n"
		++ bar
		++ outputs
		++ bar
-- 		++ "-- Types                                                                    --\n"
-- 		++ bar
-- 		++ types
-- 		++ bar
		++ "-- Entities                                                                 --\n"
		++ bar
		++ circuit
		++ bar

	return $ msg

debugCircuit :: (Ports circuit) => [ReifyOptions] -> circuit -> IO ()
debugCircuit opt c = showReifiedCircuit opt c >>= putStr



-- | The 'Ports' class generates input pads for a function type, so that the
-- function can be Reified. The result of the circuit, as a driver, as well as
-- the result's type, are returned. I _think_ this takes the place of the REIFY
-- typeclass, but I'm not really sure.

class Ports a where
  ports :: [String] -> a -> (BaseTy, Driver E)

instance OpType a => Ports (Signal a) where
  ports _ sig@(Signal _ d) =  (bitTypeOf sig, d)

instance (OpType a, OpType b) => Ports (Signal a, Signal b) where
  ports _ (aSig@(Signal _ da), bSig@(Signal _ db)) =
            (U size,
               Port (Var "o0")
            $ E
            $ Entity (Name "Lava" "top") [(Var "o0",U size)]
             [(Var "i0", aTy, da),
              (Var "i1",bTy, db)
             ] [])
    where aTy = bitTypeOf aSig
          bTy = bitTypeOf bSig
          size = baseTypeLength aTy  + baseTypeLength bTy

instance (OpType a, OpType b, OpType c) => Ports (Signal a, Signal b, Signal c) where
  ports _ (aSig@(Signal _ da), bSig@(Signal _ db),  cSig@(Signal _ dc)) =
            (U size,
               Port (Var "o0")
            $ E
            $ Entity (Name "Lava" "top") [(Var "o0",U size)]
             [(Var "i0", aTy, da),
              (Var "i1",bTy, db),
              (Var "i2",cTy, dc)
             ] [])
    where aTy = bitTypeOf aSig
          bTy = bitTypeOf bSig
          cTy = bitTypeOf cSig
          size = baseTypeLength aTy  + baseTypeLength bTy + baseTypeLength cTy

instance (OpType a, OpType b, OpType c, OpType d) => Ports (Signal a, Signal b, Signal c, Signal d) where
  ports _ (aSig@(Signal _ da), bSig@(Signal _ db),  cSig@(Signal _ dc),   dSig@(Signal _ dd)) =
            (U size,
               Port (Var "o0")
            $ E
            $ Entity (Name "Lava" "top") [(Var "o0",U size)]
             [(Var "i0", aTy, da),
              (Var "i1",bTy, db),
              (Var "i2",cTy, dc),
              (Var "i2",dTy, dd)
             ] [])
    where aTy = bitTypeOf aSig
          bTy = bitTypeOf bSig
          cTy = bitTypeOf cSig
          dTy = bitTypeOf dSig
          size = baseTypeLength aTy  + baseTypeLength bTy + baseTypeLength cTy + baseTypeLength dTy



instance (OpType a, Ports b) => Ports (Signal a -> b) where
  ports (v:vs) f = ports vs $ f (Signal (error "Ports(Signal a -> b)") (Pad (Var v)))
  ports _ _ = error "Ports.ports (Signal a -> b)"

instance Ports b => Ports (Time -> b) where
  ports vs f = ports vs $ f'
    where f' c r = f (Time c r)

instance (OpType a, OpType b, Ports c) => Ports ((Signal a, Signal b) -> c) where
  ports vs f = ports vs (curry f)


instance (OpType a, OpType b, OpType c, Ports d) => Ports ((Signal a, Signal b, Signal c) -> d) where
  ports vs f = ports vs (curry3 f)
     where curry3 f a b c = f (a,b,c)


