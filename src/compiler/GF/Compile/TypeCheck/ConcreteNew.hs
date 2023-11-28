{-# LANGUAGE RankNTypes, CPP #-}
module GF.Compile.TypeCheck.ConcreteNew( checkLType, inferLType ) where

-- The code here is based on the paper:
-- Simon Peyton Jones, Dimitrios Vytiniotis, Stephanie Weirich.
-- Practical type inference for arbitrary-rank types.
-- 14 September 2011

import GF.Grammar hiding (Env, VGen, VApp, VRecType)
import GF.Grammar.Lookup
import GF.Grammar.Predef
import GF.Grammar.Lockfield
import GF.Compile.Compute.Concrete
import GF.Infra.CheckM
import GF.Data.Operations
import Control.Applicative(Applicative(..))
import Control.Monad(ap,liftM,mplus,foldM,zipWithM)
import Control.Monad.ST
import GF.Text.Pretty
import Data.STRef
import Data.List (nub, (\\), tails)
import qualified Data.Map as Map
import Data.Maybe(fromMaybe,isNothing)
import qualified Control.Monad.Fail as Fail

checkLType :: Grammar -> Term -> Type -> Check (Term, Type)
checkLType gr t ty = runEvalOneM gr $ do
  vty <- eval [] ty []
  (t,_) <- tcRho [] t (Just vty)
  t <- zonkTerm t
  return (t,ty)

inferLType :: Grammar -> Term -> Check (Term, Type)
inferLType gr t = runEvalOneM gr $ do
  (t,ty) <- inferSigma [] t
  t  <- zonkTerm t
  ty <- zonkTerm =<< value2term [] ty
  return (t,ty)

inferSigma :: Scope s -> Term -> EvalM s (Term,Sigma s)
inferSigma scope t = do                                      -- GEN1
  (t,ty) <- tcRho scope t Nothing
  env_tvs <- getMetaVars (scopeTypes scope)
  res_tvs <- getMetaVars [(scope,ty)]
  let forall_tvs = res_tvs \\ env_tvs
  quantify scope t forall_tvs ty

vtypeInt   = VApp (cPredef,cInt) []
vtypeFloat = VApp (cPredef,cFloat) []
vtypeInts i= newEvaluatedThunk (VInt i) >>= \tnk -> return (VApp (cPredef,cInts) [tnk])
vtypeStr   = VSort cStr
vtypeStrs  = VSort cStrs
vtypeType  = VSort cType
vtypePType = VSort cPType

tcRho :: Scope s -> Term -> Maybe (Rho s) -> EvalM s (Term, Rho s)
tcRho scope t@(EInt i)   mb_ty = vtypeInts i >>= \sigma -> instSigma scope t sigma mb_ty -- INT
tcRho scope t@(EFloat _) mb_ty = instSigma scope t vtypeFloat mb_ty    -- FLOAT
tcRho scope t@(K _)      mb_ty = instSigma scope t vtypeStr   mb_ty    -- STR
tcRho scope t@(Empty)    mb_ty = instSigma scope t vtypeStr   mb_ty
tcRho scope t@(Vr v)     mb_ty = do                          -- VAR
  case lookup v scope of
    Just v_sigma -> instSigma scope t v_sigma mb_ty
    Nothing      -> evalError ("Unknown variable" <+> v)
tcRho scope t@(Q id)     mb_ty = do
  (t,ty) <- tcApp scope t t
  instSigma scope t ty mb_ty
tcRho scope t@(QC id)    mb_ty = do
  (t,ty) <- tcApp scope t t
  instSigma scope t ty mb_ty
tcRho scope t@(App fun arg) mb_ty = do
  (t,ty) <- tcApp scope t t
  instSigma scope t ty mb_ty
tcRho scope (Abs bt var body) Nothing = do                   -- ABS1
  (_,tnk) <- newResiduation scope vtypeType
  env <- scopeEnv scope
  let arg_ty = VMeta tnk env []
  (body,body_ty) <- tcRho ((var,arg_ty):scope) body Nothing
  return (Abs bt var body, (VProd bt identW arg_ty body_ty))
tcRho scope t@(Abs Implicit var body) (Just ty) = do         -- ABS2
  (bt, _, var_ty, body_ty) <- unifyFun scope ty
  if bt == Implicit
    then return ()
    else evalError (ppTerm Unqualified 0 t <+> "is an implicit function, but no implicit function is expected")
  (body, body_ty) <- tcRho ((var,var_ty):scope) body (Just body_ty)
  return (Abs Implicit var body,ty)
tcRho scope (Abs Explicit var body) (Just ty) = do           -- ABS3
  (scope,f,ty') <- skolemise scope ty
  (_,_,var_ty,body_ty) <- unifyFun scope ty'
  (body, body_ty) <- tcRho ((var,var_ty):scope) body (Just body_ty)
  return (f (Abs Explicit var body),ty)
tcRho scope (Meta i) (Just ty) = do
  (i,_) <- newResiduation scope ty
  return (Meta i, ty)
tcRho scope (Meta _) Nothing = do
  (_,tnk) <- newResiduation scope vtypeType
  env <- scopeEnv scope
  let vty = VMeta tnk env []
  (i,_) <- newResiduation scope vty
  return (Meta i, vty)
tcRho scope (Let (var, (mb_ann_ty, rhs)) body) mb_ty = do    -- LET
  (rhs,var_ty) <- case mb_ann_ty of
                    Nothing     -> inferSigma scope rhs
                    Just ann_ty -> do (ann_ty, _) <- tcRho scope ann_ty (Just vtypeType)
                                      env <- scopeEnv scope
                                      v_ann_ty <- eval env ann_ty []
                                      (rhs,_) <- tcRho scope rhs (Just v_ann_ty)
                                      return (rhs, v_ann_ty)
  (body, body_ty) <- tcRho ((var,var_ty):scope) body mb_ty
  var_ty <- value2term (scopeVars scope) var_ty
  return (Let (var, (Just var_ty, rhs)) body, body_ty)
tcRho scope (Typed body ann_ty) mb_ty = do                   -- ANNOT
  (ann_ty, _) <- tcRho scope ann_ty (Just vtypeType)
  env <- scopeEnv scope
  v_ann_ty <- eval env ann_ty []
  (body,_) <- tcRho scope body (Just v_ann_ty)
  instSigma scope (Typed body ann_ty) v_ann_ty mb_ty
tcRho scope (FV ts) mb_ty = do
  case ts of
    []     -> do (i,tnk) <- newResiduation scope vtypeType
                 env <- scopeEnv scope
                 instSigma scope (FV []) (VMeta tnk env []) mb_ty
    (t:ts) -> do (t,ty) <- tcRho scope t mb_ty

                 let go []     ty = return ([],ty)
                     go (t:ts) ty = do (t, ty) <- tcRho scope t (Just ty)
                                       (ts,ty) <- go ts ty
                                       return (t:ts,ty)

                 (ts,ty) <- go ts ty
                 return (FV (t:ts), ty)
tcRho scope t@(Sort s) mb_ty = do
  instSigma scope t vtypeType mb_ty
tcRho scope t@(RecType rs) Nothing   = do
  (rs,mb_ty) <- tcRecTypeFields scope rs Nothing
  return (RecType rs,fromMaybe vtypePType mb_ty)
tcRho scope t@(RecType rs) (Just ty) = do
  (scope,f,ty') <- skolemise scope ty
  case ty' of
    VSort s
      | s == cType  -> return ()
      | s == cPType -> return ()
    VMeta i env vs  -> case rs of
                         [] -> unifyVar scope i env vs vtypePType
                         _  -> return ()
    ty              -> do ty <- zonkTerm =<< value2term (scopeVars scope) ty
                          evalError ("The record type" <+> ppTerm Unqualified 0 t $$
                                     "cannot be of type" <+> ppTerm Unqualified 0 ty)
  (rs,mb_ty) <- tcRecTypeFields scope rs (Just ty')
  return (f (RecType rs),ty)
tcRho scope t@(Table p res) mb_ty = do
  (p,  p_ty)   <- tcRho scope p   (Just vtypePType)
  (res,res_ty) <- tcRho scope res (Just vtypeType)
  instSigma scope (Table p res) vtypeType mb_ty
tcRho scope (Prod bt x ty1 ty2) mb_ty = do
  (ty1,ty1_ty) <- tcRho scope ty1 (Just vtypeType)
  env <- scopeEnv scope
  vty1 <- eval env ty1 []
  (ty2,ty2_ty) <- tcRho ((x,vty1):scope) ty2 (Just vtypeType)
  instSigma scope (Prod bt x ty1 ty2) vtypeType mb_ty
tcRho scope (S t p) mb_ty = do
  env <- scopeEnv scope
  let mk_val (_,tnk) = VMeta tnk env []
  p_ty   <- fmap mk_val $ newResiduation scope vtypePType
  res_ty <- case mb_ty of
              Nothing -> fmap mk_val $ newResiduation scope vtypeType
              Just ty -> return ty
  let t_ty = VTable p_ty res_ty
  (t,t_ty) <- tcRho scope t (Just t_ty)
  (p,_) <- tcRho scope p (Just p_ty)
  return (S t p, res_ty)
tcRho scope (T tt ps) Nothing = do                           -- ABS1/AABS1 for tables
  env <- scopeEnv scope
  let mk_val (_,tnk) = VMeta tnk env []
  p_ty   <- case tt of
              TRaw      -> fmap mk_val $ newResiduation scope vtypePType
              TTyped ty -> do (ty, _) <- tcRho scope ty (Just vtypeType)
                              eval env ty []
  (ps,mb_res_ty) <- tcCases scope ps p_ty Nothing
  res_ty <- case mb_res_ty of
              Just res_ty -> return res_ty
              Nothing     -> fmap mk_val $ newResiduation scope vtypeType
  p_ty_t <- value2term [] p_ty
  return (T (TTyped p_ty_t) ps, VTable p_ty res_ty)
tcRho scope (T tt ps) (Just ty) = do                         -- ABS2/AABS2 for tables
  (scope,f,ty') <- skolemise scope ty
  (p_ty, res_ty) <- unifyTbl scope ty'
  case tt of
    TRaw      -> return ()
    TTyped ty -> do (ty, _) <- tcRho scope ty (Just vtypeType)
                    return ()--subsCheckRho ge scope -> Term ty res_ty
  (ps,Just res_ty) <- tcCases scope ps p_ty (Just res_ty)
  p_ty_t <- value2term [] p_ty
  return (f (T (TTyped p_ty_t) ps), VTable p_ty res_ty)
tcRho scope (R rs) Nothing = do
  lttys <- inferRecFields scope rs
  rs <- mapM (\(l,t,ty) -> value2term (scopeVars scope) ty >>= \ty -> return (l, (Just ty, t))) lttys
  return (R        rs,
          VRecType [(l, ty) | (l,t,ty) <- lttys]
         )
tcRho scope (R rs) (Just ty) = do
  (scope,f,ty') <- skolemise scope ty
  case ty' of
    (VRecType ltys) -> do lttys <- checkRecFields scope rs ltys
                          rs <- mapM (\(l,t,ty) -> value2term (scopeVars scope) ty >>= \ty -> return (l, (Just ty, t))) lttys
                          return ((f . R)  rs,
                                  VRecType [(l, ty) | (l,t,ty) <- lttys]
                                 )
    ty              -> do lttys <- inferRecFields scope rs
                          t <- liftM (f . R) (mapM (\(l,t,ty) -> value2term (scopeVars scope) ty >>= \ty -> return (l, (Just ty, t))) lttys)
                          let ty' = VRecType [(l, ty) | (l,t,ty) <- lttys]
                          t <- subsCheckRho scope t ty' ty
                          return (t, ty')
tcRho scope (P t l) mb_ty = do
  l_ty   <- case mb_ty of
              Just ty -> return ty
              Nothing -> do env <- scopeEnv scope
                            (i,tnk) <- newResiduation scope vtypeType
                            return (VMeta tnk env [])
  (t,t_ty) <- tcRho scope t (Just (VRecType [(l,l_ty)]))
  return (P t l,l_ty)
tcRho scope (C t1 t2) mb_ty = do
  (t1,t1_ty) <- tcRho scope t1 (Just vtypeStr)
  (t2,t2_ty) <- tcRho scope t2 (Just vtypeStr)
  instSigma scope (C t1 t2) vtypeStr mb_ty
tcRho scope (Glue t1 t2) mb_ty = do
  (t1,t1_ty) <- tcRho scope t1 (Just vtypeStr)
  (t2,t2_ty) <- tcRho scope t2 (Just vtypeStr)
  instSigma scope (Glue t1 t2) vtypeStr mb_ty
tcRho scope t@(ExtR t1 t2) mb_ty = do
  (t1,t1_ty) <- tcRho scope t1 Nothing
  (t2,t2_ty) <- tcRho scope t2 Nothing
  case (t1_ty,t2_ty) of
    (VSort s1,VSort s2)
       | (s1 == cType || s1 == cPType) &&
         (s2 == cType || s2 == cPType) -> let sort | s1 == cPType && s2 == cPType = cPType
                                                   | otherwise                    = cType
                                          in instSigma scope (ExtR t1 t2) (VSort sort) mb_ty
    (VRecType rs1, VRecType rs2)       -> instSigma scope (ExtR t1 t2) (VRecType (rs2++rs1)) mb_ty
    _                                  -> evalError ("Cannot type check" <+> ppTerm Unqualified 0 t)
tcRho scope (ELin cat t) mb_ty = do  -- this could be done earlier, i.e. in the parser
  tcRho scope (ExtR t (R [(lockLabel cat,(Just (RecType []),R []))])) mb_ty
tcRho scope (ELincat cat t) mb_ty = do  -- this could be done earlier, i.e. in the parser
  tcRho scope (ExtR t (RecType [(lockLabel cat,RecType [])])) mb_ty
tcRho scope (Alts t ss) mb_ty = do
  (t,_) <- tcRho scope t (Just vtypeStr)
  ss    <- flip mapM ss $ \(t1,t2) -> do
              (t1,_) <- tcRho scope t1 (Just vtypeStr)
              (t2,_) <- tcRho scope t2 (Just vtypeStrs)
              return (t1,t2)
  instSigma scope (Alts t ss) vtypeStr mb_ty
tcRho scope (Strs ss) mb_ty = do
  ss <- flip mapM ss $ \t -> do
           (t,_) <- tcRho scope t (Just vtypeStr)
           return t
  instSigma scope (Strs ss) vtypeStrs mb_ty
tcRho scope (EPattType ty) mb_ty = do
  (ty, _) <- tcRho scope ty (Just vtypeType)
  instSigma scope (EPattType ty) vtypeType mb_ty
tcRho scope t@(EPatt min max p) mb_ty = do
  (scope,f,ty) <- case mb_ty of
                    Nothing -> do env <- scopeEnv scope
                                  (i,tnk) <- newResiduation scope vtypeType
                                  return (scope,id,VMeta tnk env [])
                    Just ty -> do (scope,f,ty) <- skolemise scope ty
                                  case ty of
                                    VPattType ty -> return (scope,f,ty)
                                    _            -> evalError (ppTerm Unqualified 0 t <+> "must be of pattern type but" <+> ppTerm Unqualified 0 t <+> "is expected")
  tcPatt scope p ty
  return (f (EPatt min max p), ty)
tcRho scope t _ = unimplemented ("tcRho "++show t)

tcCases scope []         p_ty mb_res_ty = return ([],mb_res_ty)
tcCases scope ((p,t):cs) p_ty mb_res_ty = do
  scope' <- tcPatt scope p p_ty
  (t,res_ty)     <- tcRho scope' t mb_res_ty
  (cs,mb_res_ty) <- tcCases scope cs p_ty (Just res_ty)
  return ((p,t):cs,mb_res_ty)

tcApp scope t0 t@(App fun (ImplArg arg)) = do                  -- APP1
  (fun,fun_ty) <- tcApp scope t0 fun
  (bt, _, arg_ty, res_ty) <- unifyFun scope fun_ty
  if (bt == Implicit)
    then return ()
    else evalError (ppTerm Unqualified 0 t <+> "is an implicit argument application, but no implicit argument is expected")
  (arg,_) <- tcRho scope arg (Just arg_ty)
  env <- scopeEnv scope
  varg <- eval env arg []
  return (App fun (ImplArg arg), res_ty)
tcApp scope t0 (App fun arg) = do                              -- APP2
  (fun,fun_ty) <- tcApp scope t0 fun
  (fun,fun_ty) <- instantiate scope fun fun_ty
  (_, x, arg_ty, res_ty) <- unifyFun scope fun_ty
  (arg,_) <- tcRho scope arg (Just arg_ty)
  res_ty <- case res_ty of
              VClosure res_env res_ty -> do env <- scopeEnv scope
                                            tnk <- newThunk env arg
                                            eval ((x,tnk):res_env) res_ty []
              res_ty                  -> return res_ty
  return (App fun arg, res_ty)
tcApp scope t0 (Q id)  = do                                    -- VAR (global)
  (t,ty) <- getOverload t0 id
  vty <- eval [] ty []
  return (t,vty)
tcApp scope t0 (QC id) = do                                    -- VAR (global)
  (t,ty) <- getOverload t0 id
  vty <- eval [] ty []
  return (t,vty)
tcApp scope t0 t = tcRho scope t Nothing

tcOverloadFailed t ttys =
  evalError ("Overload resolution failed" $$
             "of term   " <+> pp t $$
             "with types" <+> vcat [ppTerm Terse 0 ty | (_,ty) <- ttys])


tcPatt scope PW        ty0 =
  return scope
tcPatt scope (PV x)    ty0 =
  return ((x,ty0):scope)
tcPatt scope (PP c ps) ty0 = do
  ty <- getResType c
  let go scope ty []     = return (scope,ty)
      go scope ty (p:ps) = do (_,_,arg_ty,res_ty) <- unifyFun scope ty
                              scope <- tcPatt scope p arg_ty
                              go scope res_ty ps
  vty <- eval [] ty []
  (scope,ty) <- go scope vty ps
  unify scope ty0 ty
  return scope
tcPatt scope (PInt i) ty0 = do
  ty <- vtypeInts i
  subsCheckRho scope (EInt i) ty ty0
  return scope
tcPatt scope (PString s) ty0 = do
  unify scope ty0 vtypeStr
  return scope
tcPatt scope PChar ty0 = do
  unify scope ty0 vtypeStr
  return scope
tcPatt scope (PSeq _ _ p1 _ _ p2) ty0 = do
  unify scope ty0 vtypeStr
  scope <- tcPatt scope p1 vtypeStr
  scope <- tcPatt scope p2 vtypeStr
  return scope
tcPatt scope (PAs x p) ty0 = do
  tcPatt ((x,ty0):scope) p ty0
tcPatt scope (PR rs) ty0 = do
  let mk_ltys  []            = return []
      mk_ltys  ((l,p):rs)    = do (_,tnk) <- newResiduation scope vtypePType
                                  ltys <- mk_ltys rs
                                  env <- scopeEnv scope
                                  return ((l,p,VMeta tnk env []) : ltys)
      go scope []            = return scope
      go scope ((l,p,ty):rs) = do scope <- tcPatt scope p ty
                                  go scope rs
  ltys <- mk_ltys rs
  subsCheckRho scope (EPatt 0 Nothing (PR rs)) (VRecType [(l,ty) | (l,p,ty) <- ltys]) ty0
  go scope ltys
tcPatt scope (PAlt p1 p2) ty0 = do
  tcPatt scope p1 ty0
  tcPatt scope p2 ty0
  return scope
tcPatt scope (PM q) ty0 = do
  ty <- getResType q
  case ty of
    EPattType ty
            -> do vty <- eval [] ty []
                  unify scope ty0 vty
                  return scope
    ty   -> evalError ("Pattern type expected but " <+> pp ty <+> " found.")
tcPatt scope p ty = unimplemented ("tcPatt "++show p)

inferRecFields scope rs =
  mapM (\(l,r) -> tcRecField scope l r Nothing) rs

checkRecFields scope []          ltys
  | null ltys                            = return []
  | otherwise                            = evalError ("Missing fields:" <+> hsep (map fst ltys))
checkRecFields scope ((l,t):lts) ltys =
  case takeIt l ltys of
    (Just ty,ltys) -> do ltty  <- tcRecField scope l t (Just ty)
                         lttys <- checkRecFields scope lts ltys
                         return (ltty : lttys)
    (Nothing,ltys) -> do evalWarn ("Discarded field:" <+> l)
                         ltty  <- tcRecField scope l t Nothing
                         lttys <- checkRecFields scope lts ltys
                         return lttys     -- ignore the field
  where
    takeIt l1 []  = (Nothing, [])
    takeIt l1 (lty@(l2,ty):ltys)
      | l1 == l2  = (Just ty,ltys)
      | otherwise = let (mb_ty,ltys') = takeIt l1 ltys
                    in (mb_ty,lty:ltys')

tcRecField scope l (mb_ann_ty,t) mb_ty = do
  (t,ty) <- case mb_ann_ty of
              Just ann_ty -> do (ann_ty, _) <- tcRho scope ann_ty (Just vtypeType)
                                env <- scopeEnv scope
                                v_ann_ty <- eval env ann_ty []
                                (t,_) <- tcRho scope t (Just v_ann_ty)
                                instSigma scope t v_ann_ty mb_ty
              Nothing     -> tcRho scope t mb_ty
  return (l,t,ty)

tcRecTypeFields scope []          mb_ty = return ([],mb_ty)
tcRecTypeFields scope ((l,ty):rs) mb_ty = do
  (ty,sort) <- tcRho scope ty mb_ty
  mb_ty <- case sort of
             VSort s
               | s == cType  -> return (Just sort)
               | s == cPType -> return mb_ty
             VMeta _ _ _     -> return mb_ty
             _               -> do sort <- zonkTerm =<< value2term (scopeVars scope) sort
                                   evalError ("The record type field" <+> l <+> ':' <+> ppTerm Unqualified 0 ty $$
                                              "cannot be of type" <+> ppTerm Unqualified 0 sort)
  (rs,mb_ty) <- tcRecTypeFields scope rs mb_ty
  return ((l,ty):rs,mb_ty)

-- | Invariant: if the third argument is (Just rho),
--              then rho is in weak-prenex form
instSigma :: Scope s -> Term -> Sigma s -> Maybe (Rho s) -> EvalM s (Term, Rho s)
instSigma scope t ty1 Nothing    = return (t,ty1)           -- INST1
instSigma scope t ty1 (Just ty2) = do                       -- INST2
  t <- subsCheckRho scope t ty1 ty2
  return (t,ty2)

-- | Invariant: the second argument is in weak-prenex form
subsCheckRho :: Scope s -> Term -> Sigma s -> Rho s -> EvalM s Term
subsCheckRho scope t ty1@(VMeta i env vs) ty2 = do
  mv <- getRef i
  case mv of
    Residuation _ _ _ -> do unify scope ty1 ty2
                            return t
    Bound ty1         -> do vty1 <- eval env ty1 vs
                            subsCheckRho scope t vty1 ty2
subsCheckRho scope t ty1 ty2@(VMeta i env vs) = do
  mv <- getRef i
  case mv of
    Residuation _ _ _ -> do unify scope ty1 ty2
                            return t
    Bound ty2         -> do vty2 <- eval env ty2 vs
                            subsCheckRho scope t ty1 vty2
subsCheckRho scope t (VProd Implicit x ty1 ty2) rho2 = do     -- Rule SPEC
  (i,tnk) <- newResiduation scope ty1
  ty2 <- case ty2 of
           VClosure env ty2 -> eval ((x,tnk):env) ty2 []
           ty2              -> return ty2
  subsCheckRho scope (App t (ImplArg (Meta i))) ty2 rho2
subsCheckRho scope t rho1 (VProd Implicit x ty1 ty2) = do     -- Rule SKOL
  let v = newVar scope
  ty2 <- case ty2 of
           VClosure env ty2 -> do tnk <- newEvaluatedThunk (VGen (length scope) [])
                                  eval ((x,tnk):env) ty2 []
           ty2              -> return ty2
  t <- subsCheckRho ((v,ty1):scope) t rho1 ty2
  return (Abs Implicit v t)
subsCheckRho scope t rho1 (VProd Explicit _ a2 r2) = do       -- Rule FUN
  (_,_,a1,r1) <- unifyFun scope rho1
  subsCheckFun scope t a1 r1 a2 r2
subsCheckRho scope t (VProd Explicit _ a1 r1) rho2 = do       -- Rule FUN
  (_,_,a2,r2) <- unifyFun scope rho2
  subsCheckFun scope t a1 r1 a2 r2
subsCheckRho scope t rho1 (VTable p2 r2) = do                 -- Rule TABLE
  (p1,r1) <- unifyTbl scope rho1
  subsCheckTbl scope t p1 r1 p2 r2
subsCheckRho scope t (VTable p1 r1) rho2 = do                 -- Rule TABLE
  (p2,r2) <- unifyTbl scope rho2
  subsCheckTbl scope t p1 r1 p2 r2
subsCheckRho scope t (VSort s1) (VSort s2)                    -- Rule PTYPE
  | s1 == cPType && s2 == cType = return t
subsCheckRho scope t (VApp p1 _) (VApp p2 _)                  -- Rule INT1
  | p1 == (cPredef,cInts) && p2 == (cPredef,cInt) = return t
subsCheckRho scope t (VApp p1 [tnk1]) (VApp p2 [tnk2])        -- Rule INT2
  | p1 == (cPredef,cInts) && p2 == (cPredef,cInts) = do
      VInt i <- force tnk1
      VInt j <- force tnk2
      if i <= j
        then return t
        else evalError ("Ints" <+> i <+> "is not a subtype of" <+> "Ints" <+> j)
subsCheckRho scope t ty1@(VRecType rs1) ty2@(VRecType rs2) = do      -- Rule REC
  let mkAccess scope t =
        case t of
          ExtR t1 t2 -> do (scope,mkProj1,mkWrap1) <- mkAccess scope t1
                           (scope,mkProj2,mkWrap2) <- mkAccess scope t2
                           return (scope
                                  ,\l -> mkProj2 l `mplus` mkProj1 l
                                  ,mkWrap1 . mkWrap2
                                  )
          R rs -> do sequence_ [evalWarn ("Discarded field:" <+> l) | (l,_) <- rs, isNothing (lookup l rs2)]
                     return (scope
                            ,\l -> lookup l rs
                            ,id
                            )
          Vr x -> do return (scope
                            ,\l -> do VRecType rs <- lookup x scope
                                      ty <- lookup l rs
                                      return (Nothing,P t l)
                            ,id
                            )
          t    -> let x = newVar scope
                  in return (((x,ty1):scope)
                            ,\l  -> return (Nothing,P (Vr x) l)
                            ,Let (x, (Nothing, t))
                            )

      mkField scope l (mb_ty,t) ty1 ty2 = do
        t <- subsCheckRho scope t ty1 ty2
        return (l, (mb_ty,t))

  (scope,mkProj,mkWrap) <- mkAccess scope t

  let fields = [(l,ty2,lookup l rs1) | (l,ty2) <- rs2]
  case [l | (l,_,Nothing) <- fields] of
    []      -> return ()
    missing -> evalError ("In the term" <+> pp t $$
                          "there are no values for fields:" <+> hsep missing)
  rs <- sequence [mkField scope l t ty1 ty2 | (l,ty2,Just ty1) <- fields, Just t <- [mkProj l]]
  return (mkWrap (R rs))
subsCheckRho scope t tau1 tau2 = do                           -- Rule EQ
  unify scope tau1 tau2                                 -- Revert to ordinary unification
  return t

subsCheckFun :: Scope s -> Term -> Sigma s -> Value s -> Sigma s -> Value s -> EvalM s Term
subsCheckFun scope t a1 r1 a2 r2 = do
  let v   = newVar scope
  vt <- subsCheckRho ((v,a2):scope) (Vr v) a2 a1
  tnk <- newEvaluatedThunk (VGen (length scope) [])
  r1 <- case r1 of
          VClosure env r1 -> eval ((v,tnk):env) r1 []
          r1              -> return r1
  r2 <- case r2 of
          VClosure env r2 -> eval ((v,tnk):env) r2 []
          r2              -> return r2
  t  <- subsCheckRho ((v,vtypeType):scope) (App t vt) r1 r2
  return (Abs Explicit v t)

subsCheckTbl :: Scope s -> Term -> Sigma s -> Rho s -> Sigma s -> Rho s -> EvalM s Term
subsCheckTbl scope t p1 r1 p2 r2 = do
  let x = newVar scope
  xt <- subsCheckRho scope (Vr x) p2 p1
  t  <- subsCheckRho ((x,vtypePType):scope) (S t xt) r1 r2
  p2 <- value2term (scopeVars scope) p2
  return (T (TTyped p2) [(PV x,t)])

-----------------------------------------------------------------------
-- Unification
-----------------------------------------------------------------------

unifyFun :: Scope s -> Rho s -> EvalM s (BindType, Ident, Sigma s, Rho s)
unifyFun scope (VProd bt x arg res) =
  return (bt,x,arg,res)
unifyFun scope tau = do
  let mk_val (_,tnk) = VMeta tnk [] []
  arg <- fmap mk_val $ newResiduation scope vtypeType
  res <- fmap mk_val $ newResiduation scope vtypeType
  let bt = Explicit
  unify scope tau (VProd bt identW arg res)
  return (bt,identW,arg,res)

unifyTbl :: Scope s -> Rho s -> EvalM s (Sigma s, Rho s)
unifyTbl scope (VTable arg res) =
  return (arg,res)
unifyTbl scope tau = do
  env <- scopeEnv scope
  let mk_val (i,tnk) = VMeta tnk env []
  arg <- fmap mk_val $ newResiduation scope vtypePType
  res <- fmap mk_val $ newResiduation scope vtypeType
  unify scope tau (VTable arg res)
  return (arg,res)

unify scope (VApp f1 vs1)      (VApp f2 vs2)
  | f1 == f2                   = sequence_ (zipWith (unifyThunk scope) vs1 vs2)
unify scope (VSort s1)         (VSort s2)
  | s1 == s2                   = return ()
unify scope (VGen i vs1)       (VGen j vs2)
  | i == j                     = sequence_ (zipWith (unifyThunk scope) vs1 vs2)
unify scope (VTable p1 res1) (VTable p2 res2) = do
  unify scope p1   p2
  unify scope res1 res2
unify scope (VMeta i env1 vs1) (VMeta j env2 vs2)
  | i  == j                    = sequence_ (zipWith (unifyThunk scope) vs1 vs2)
  | otherwise                  = do mv <- getRef j
                                    case mv of
                                      Bound t2          -> do v2 <- eval env2 t2 vs2
                                                              unify scope (VMeta i env1 vs1) v2
                                      Residuation j _ _ -> setRef i (Bound (Meta j))
unify scope (VInt i)       (VInt j)
  | i == j                     = return ()
unify scope (VMeta i env vs) v = unifyVar scope i env vs v
unify scope v (VMeta i env vs) = unifyVar scope i env vs v
unify scope v1 v2 = do
  t1 <- value2term (scopeVars scope) v1
  t2 <- value2term (scopeVars scope) v2
  evalError ("Cannot unify terms:" <+> (ppTerm Unqualified 0 t1 $$
                                        ppTerm Unqualified 0 t2))

unifyThunk scope tnk1 tnk2 = do
  res1 <- getRef tnk1
  res2 <- getRef tnk2
  case (res1,res2) of
    (Evaluated _ v1,Evaluated _ v2) -> unify scope v1 v2

-- | Invariant: tv1 is a flexible type variable
unifyVar :: Scope s -> Thunk s -> Env s -> [Thunk s] -> Tau s -> EvalM s ()
unifyVar scope tnk env vs ty2 = do            -- Check whether i is bound
  mv <- getRef tnk
  case mv of
    Bound ty1              -> do v <- eval env ty1 vs
                                 unify scope v ty2
    Residuation i scope' _ -> do ty2' <- value2term (scopeVars scope') ty2
                                 ms2 <- getMetaVars [(scope,ty2)]
                                 if tnk `elem` ms2
                                   then evalError ("Occurs check for" <+> ppMeta i <+> "in:" $$
                                                   nest 2 (ppTerm Unqualified 0 ty2'))
                                   else setRef tnk (Bound ty2')

-----------------------------------------------------------------------
-- Instantiation and quantification
-----------------------------------------------------------------------

-- | Instantiate the topmost implicit arguments with metavariables
instantiate :: Scope s -> Term -> Sigma s -> EvalM s (Term,Rho s)
instantiate scope t (VProd Implicit x ty1 ty2) = do
  (i,tnk) <- newResiduation scope ty1
  ty2 <- case ty2 of
           VClosure env ty2 -> eval ((x,tnk):env) ty2 []
           ty2              -> return ty2
  instantiate scope (App t (ImplArg (Meta i))) ty2
instantiate scope t ty = do
  return (t,ty)

-- | Build fresh lambda abstractions for the topmost implicit arguments
skolemise :: Scope s -> Sigma s -> EvalM s (Scope s, Term->Term, Rho s)
skolemise scope ty@(VMeta i env vs) = do
  mv <- getRef i
  case mv of
    Residuation _ _ _ -> return (scope,id,ty)                   -- guarded constant?
    Bound ty          -> do ty <- eval env ty vs
                            skolemise scope ty
skolemise scope (VProd Implicit x ty1 ty2) = do
  let v = newVar scope
  ty2 <- case ty2 of
           VClosure env ty2 -> do tnk <- newEvaluatedThunk (VGen (length scope) [])
                                  eval ((x,tnk) : env) ty2 []
           ty2              -> return ty2
  (scope,f,ty2) <- skolemise ((v,ty1):scope) ty2
  return (scope,Abs Implicit v . f,ty2)
skolemise scope ty = do
  return (scope,id,ty)

-- | Quantify over the specified type variables (all flexible)
quantify :: Scope s -> Term -> [Thunk s] -> Rho s -> EvalM s (Term,Sigma s)
quantify scope t tvs ty = do
  let used_bndrs = nub (bndrs ty)  -- Avoid quantified type variables in use
      new_bndrs  = take (length tvs) (allBinders \\ used_bndrs)
  env <- scopeEnv ([(v,vtypeType) | v <- new_bndrs]++scope)
  mapM_ (bind env) (zip tvs new_bndrs)
  let vty = foldr (\v -> VProd Implicit v vtypeType) ty new_bndrs
  return (foldr (Abs Implicit) t new_bndrs,vty)
  where
    bind env (tnk, name) = setRef tnk (Bound (Vr name))

    bndrs (VProd _ x v1 v2) = [x] ++ bndrs v1  ++ bndrs v2
    bndrs _                 = []

allBinders :: [Ident]    -- a,b,..z, a1, b1,... z1, a2, b2,...
allBinders = [ identS [x]          | x <- ['a'..'z'] ] ++
             [ identS (x : show i) | i <- [1 :: Integer ..], x <- ['a'..'z']]


-----------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------

type Sigma s = Value s
type Rho s   = Value s -- No top-level ForAll
type Tau s   = Value s -- No ForAlls anywhere

unimplemented str = fail ("Unimplemented: "++str)

newVar :: Scope s -> Ident
newVar scope = head [x | i <- [1..],
                         let x = identS ('v':show i),
                         isFree scope x]
  where
    isFree []            x = True
    isFree ((y,_):scope) x = x /= y && isFree scope x

scopeEnv   scope = zipWithM (\(x,ty) i -> newEvaluatedThunk (VGen i []) >>= \tnk -> return (x,tnk)) (reverse scope) [0..]
scopeVars  scope = map fst scope
scopeTypes scope = zipWith (\(_,ty) scope -> (scope,ty)) scope (tails scope)

-- | This function takes account of zonking, and returns a set
-- (no duplicates) of unbound meta-type variables
getMetaVars :: [(Scope s,Sigma s)] -> EvalM s [Thunk s]
getMetaVars sc_tys = foldM (\acc (scope,ty) -> go ty acc) [] sc_tys
  where
    follow acc tnk = force tnk >>= \v -> go v acc

    -- Get the MetaIds from a term; no duplicates in result
    go (VSort s)          acc = return acc
    go (VInt _)           acc = return acc
    go (VRecType as)      acc = foldM (\acc (lbl,v) -> go v acc) acc as
    go (VClosure _ _)     acc = return acc
    go (VProd b x v1 v2)  acc = go v2 acc >>= go v1
    go (VTable v1 v2)     acc = go v2 acc >>= go v1
    go (VMeta m env args) acc
      | m `elem` acc          = return acc
      | otherwise             = do res <- getRef m
                                   case res of
                                     Bound _ -> return acc
                                     _       -> foldM follow (m:acc) args
    go (VApp f args)      acc = foldM follow acc args
    go v                  acc = unimplemented ("go "++showValue v)

-- | Eliminate any substitutions in a term
zonkTerm :: Term -> EvalM s Term
zonkTerm (Meta i) = do
  tnk <- EvalM $ \gr k mt d r msgs -> 
           case Map.lookup i mt of
             Just v  -> k v mt d r msgs
             Nothing -> return (Fail (pp "Undefined meta variable") msgs)
  st <- getRef tnk
  case st of
    Hole _            -> return (Meta i)
    Residuation _ _ _ -> return (Meta i)
    Narrowing _ _     -> return (Meta i)
    Bound t           -> do t <- zonkTerm t
                            setRef tnk (Bound t)     -- "Short out" multiple hops
                            return t
zonkTerm t = composOp zonkTerm t
