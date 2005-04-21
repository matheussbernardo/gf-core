
module GF.Source.SkelGF where

-- Haskell module generated by the BNF converter

import GF.Source.AbsGF
import GF.Data.ErrM
type Result = Err String

failure :: Show a => a -> Result
failure x = Bad $ "Undefined case: " ++ show x

transIdent :: Ident -> Result
transIdent x = case x of
  Ident str  -> failure x


transLString :: LString -> Result
transLString x = case x of
  LString str  -> failure x


transGrammar :: Grammar -> Result
transGrammar x = case x of
  Gr moddefs  -> failure x


transModDef :: ModDef -> Result
transModDef x = case x of
  MMain id0 id concspecs  -> failure x
  MModule complmod modtype modbody  -> failure x


transConcSpec :: ConcSpec -> Result
transConcSpec x = case x of
  ConcSpec id concexp  -> failure x


transConcExp :: ConcExp -> Result
transConcExp x = case x of
  ConcExp id transfers  -> failure x


transTransfer :: Transfer -> Result
transTransfer x = case x of
  TransferIn open  -> failure x
  TransferOut open  -> failure x


transModType :: ModType -> Result
transModType x = case x of
  MTAbstract id  -> failure x
  MTResource id  -> failure x
  MTInterface id  -> failure x
  MTConcrete id0 id  -> failure x
  MTInstance id0 id  -> failure x
  MTTransfer id open0 open  -> failure x


transModBody :: ModBody -> Result
transModBody x = case x of
  MBody extend opens topdefs  -> failure x
  MWith id opens  -> failure x
  MReuse id  -> failure x
  MUnion includeds  -> failure x


transExtend :: Extend -> Result
transExtend x = case x of
  Ext ids  -> failure x
  NoExt  -> failure x


transOpens :: Opens -> Result
transOpens x = case x of
  NoOpens  -> failure x
  Opens opens  -> failure x


transOpen :: Open -> Result
transOpen x = case x of
  OName id  -> failure x
  OQualQO qualopen id  -> failure x
  OQual qualopen id0 id  -> failure x


transComplMod :: ComplMod -> Result
transComplMod x = case x of
  CMCompl  -> failure x
  CMIncompl  -> failure x


transQualOpen :: QualOpen -> Result
transQualOpen x = case x of
  QOCompl  -> failure x
  QOIncompl  -> failure x
  QOInterface  -> failure x


transIncluded :: Included -> Result
transIncluded x = case x of
  IAll id  -> failure x
  ISome id ids  -> failure x


transDef :: Def -> Result
transDef x = case x of
  DDecl ids exp  -> failure x
  DDef ids exp  -> failure x
  DPatt id patts exp  -> failure x
  DFull ids exp0 exp  -> failure x


transTopDef :: TopDef -> Result
transTopDef x = case x of
  DefCat catdefs  -> failure x
  DefFun fundefs  -> failure x
  DefFunData fundefs  -> failure x
  DefDef defs  -> failure x
  DefData datadefs  -> failure x
  DefTrans defs  -> failure x
  DefPar pardefs  -> failure x
  DefOper defs  -> failure x
  DefLincat printdefs  -> failure x
  DefLindef defs  -> failure x
  DefLin defs  -> failure x
  DefPrintCat printdefs  -> failure x
  DefPrintFun printdefs  -> failure x
  DefFlag flagdefs  -> failure x
  DefPrintOld printdefs  -> failure x
  DefLintype defs  -> failure x
  DefPattern defs  -> failure x
  DefPackage id topdefs  -> failure x
  DefVars defs  -> failure x
  DefTokenizer id  -> failure x


transCatDef :: CatDef -> Result
transCatDef x = case x of
  CatDef id ddecls  -> failure x


transFunDef :: FunDef -> Result
transFunDef x = case x of
  FunDef ids exp  -> failure x


transDataDef :: DataDef -> Result
transDataDef x = case x of
  DataDef id dataconstrs  -> failure x


transDataConstr :: DataConstr -> Result
transDataConstr x = case x of
  DataId id  -> failure x
  DataQId id0 id  -> failure x


transParDef :: ParDef -> Result
transParDef x = case x of
  ParDef id parconstrs  -> failure x
  ParDefIndir id0 id  -> failure x
  ParDefAbs id  -> failure x


transParConstr :: ParConstr -> Result
transParConstr x = case x of
  ParConstr id ddecls  -> failure x


transPrintDef :: PrintDef -> Result
transPrintDef x = case x of
  PrintDef ids exp  -> failure x


transFlagDef :: FlagDef -> Result
transFlagDef x = case x of
  FlagDef id0 id  -> failure x


transLocDef :: LocDef -> Result
transLocDef x = case x of
  LDDecl ids exp  -> failure x
  LDDef ids exp  -> failure x
  LDFull ids exp0 exp  -> failure x


transExp :: Exp -> Result
transExp x = case x of
  EIdent id  -> failure x
  EConstr id  -> failure x
  ECons id  -> failure x
  ESort sort  -> failure x
  EString str  -> failure x
  EInt n  -> failure x
  EMeta  -> failure x
  EEmpty  -> failure x
  EData  -> failure x
  EStrings str  -> failure x
  ERecord locdefs  -> failure x
  ETuple tuplecomps  -> failure x
  EIndir id  -> failure x
  ETyped exp0 exp  -> failure x
  EProj exp label  -> failure x
  EQConstr id0 id  -> failure x
  EQCons id0 id  -> failure x
  EApp exp0 exp  -> failure x
  ETable cases  -> failure x
  ETTable exp cases  -> failure x
  EVTable exp exps  -> failure x
  ECase exp cases  -> failure x
  EVariants exps  -> failure x
  EPre exp alterns  -> failure x
  EStrs exps  -> failure x
  EConAt id exp  -> failure x
  ESelect exp0 exp  -> failure x
  ETupTyp exp0 exp  -> failure x
  EExtend exp0 exp  -> failure x
  EAbstr binds exp  -> failure x
  ECTable binds exp  -> failure x
  EProd decl exp  -> failure x
  ETType exp0 exp  -> failure x
  EConcat exp0 exp  -> failure x
  EGlue exp0 exp  -> failure x
  ELet locdefs exp  -> failure x
  ELetb locdefs exp  -> failure x
  EWhere exp locdefs  -> failure x
  EEqs equations  -> failure x
  ELString lstring  -> failure x
  ELin id  -> failure x


transPatt :: Patt -> Result
transPatt x = case x of
  PW  -> failure x
  PV id  -> failure x
  PCon id  -> failure x
  PQ id0 id  -> failure x
  PInt n  -> failure x
  PStr str  -> failure x
  PR pattasss  -> failure x
  PTup patttuplecomps  -> failure x
  PC id patts  -> failure x
  PQC id0 id patts  -> failure x


transPattAss :: PattAss -> Result
transPattAss x = case x of
  PA ids patt  -> failure x


transLabel :: Label -> Result
transLabel x = case x of
  LIdent id  -> failure x
  LVar n  -> failure x


transSort :: Sort -> Result
transSort x = case x of
  Sort_Type  -> failure x
  Sort_PType  -> failure x
  Sort_Tok  -> failure x
  Sort_Str  -> failure x
  Sort_Strs  -> failure x


transPattAlt :: PattAlt -> Result
transPattAlt x = case x of
  AltP patt  -> failure x


transBind :: Bind -> Result
transBind x = case x of
  BIdent id  -> failure x
  BWild  -> failure x


transDecl :: Decl -> Result
transDecl x = case x of
  DDec binds exp  -> failure x
  DExp exp  -> failure x


transTupleComp :: TupleComp -> Result
transTupleComp x = case x of
  TComp exp  -> failure x


transPattTupleComp :: PattTupleComp -> Result
transPattTupleComp x = case x of
  PTComp patt  -> failure x


transCase :: Case -> Result
transCase x = case x of
  Case pattalts exp  -> failure x


transEquation :: Equation -> Result
transEquation x = case x of
  Equ patts exp  -> failure x


transAltern :: Altern -> Result
transAltern x = case x of
  Alt exp0 exp  -> failure x


transDDecl :: DDecl -> Result
transDDecl x = case x of
  DDDec binds exp  -> failure x
  DDExp exp  -> failure x


transOldGrammar :: OldGrammar -> Result
transOldGrammar x = case x of
  OldGr include topdefs  -> failure x


transInclude :: Include -> Result
transInclude x = case x of
  NoIncl  -> failure x
  Incl filenames  -> failure x


transFileName :: FileName -> Result
transFileName x = case x of
  FString str  -> failure x
  FIdent id  -> failure x
  FSlash filename  -> failure x
  FDot filename  -> failure x
  FMinus filename  -> failure x
  FAddId id filename  -> failure x



