{
 {-# LANGUAGE QuasiQuotes #-}
module Language.Fortran.Parser  where

import Language.Fortran

import Traverse

import Language.Haskell.Syntax (SrcLoc,srcLine,srcColumn)
import Language.Haskell.ParseMonad 
import Language.Fortran.Lexer
import Data.Char (toLower)
-- import GHC.Exts

import Debug.Trace

import Data.Generics.Annotate
import Generics.Deriving.Copoint

-- Type of annotations

type Annotation0 = (SrcLoc, SrcLoc) 

-- Given a source location (usually token start),
-- get the current src loc from the parser monad (usually token end), 
-- return as pair giving bounds on the syntax span

srcSpan :: SrcLoc -> P Annotation0
srcSpan l = do l' <- getSrcLoc
               return $ (l, l')

srcSpanNull :: P Annotation0
srcSpanNull = do l <- getSrcLoc
                 return $ (l, l)

srcSpan' :: GCopoint d => d Annotation0 -> P Annotation0
srcSpan' x = do l' <- getSrcLoc
                return $ (fst $ gcopoint x, l')
}

%name parser
%tokentype { Token SrcLoc }

%monad { P } { >>= } { return }
%lexer { lexer } { TokEOF l }

%token
 '=>'			{ Arrow l }
 '**'			{ OpPower l }
 '//' 			{ OpConcat l }
 '=='		        { OpEQ l }
 '/='       		{ OpNE l }
 '<='		        { OpLE l }
 '>='		        { OpGE l }
 '.NOT.'		{ OpNOT l }
 '.AND.'		{ OpAND l }
 '.OR.'		        { OpOR l }
 '.TRUE.'		{ TrueConst l }
 '.FALSE.'		{ FalseConst l }
-- '.EQV.'		{ OpEQV l }
-- '.NEGV.' 	       	{ OpNEQV l }
 '<'		        { OpLT l }
 '>'		        { OpGT l }
 '*'		       	{ OpMul l }
 '/'		       	{ OpDiv l }
 '+'		       	{ OpAdd l }
 '-'		       	{ OpSub l }
 ','		       	{ Comma l }
 '('		       	{ LParen l }
 ')'		       	{ RParen l }
 '='		       	{ OpEquals l }
-- '\''		      	{ SingleQuote l }
-- '\"'			{ DoubleQuote l }
 '.'		        { Period l }
 '::'			{ ColonColon l }
 ':'			{ Colon l }
 ';'                    { SemiColon l }
 '#'                    { Hash l }
 '{'                    { LBrace l }
 '}'                    { RBrace l }
 '(/'                   { LArrCon l }
 '/)'                   { RArrCon l }
-- OBSOLETE '!'         { Bang l } 
 '%'			{ Percent l }
 '$'			{ Dollar l }
 -- OBSOLETE '!{'	{ StopParamStart l }
'\n'                    { NewLine l }
 ALLOCATE 		{ Key "allocate" l }
 ALLOCATABLE 		{ Key "allocatable" l }
-- ASSIGN 		{ Key "Assign" l }
 ASSIGNMENT 		{ Key "assignment" l }
-- AUTOMATIC 		{ Key "automatic" l }
 BACKSPACE 		{ Key "backspace" l }
 BLOCK 			{ Key "block" l }
 CALL 			{ Key "call" l }
-- CASE 		{ Key "case" l }
 CHARACTER 		{ Key "character" l }
 CLOSE 			{ Key "close" l }
 COMMON 		{ Key "common" l }
 COMPLEX 		{ Key "complex" l }
 CONTAINS 		{ Key "contains" l }
 CONTINUE 		{ Key "continue" l }
 CYCLE 			{ Key "cycle" l }
 DATA 			{ Key "data" l }
 DEALLOCATE 		{ Key "deallocate" l }
-- DEFAULT 		{ Key "default" l }
 DIMENSION 		{ Key "dimension" l }
 DO 			{ Key "do" l }
-- DOUBLE 		{ Key "double" l }
 ELEMENTAL 		{ Key "elemental" l }
 ELSE 			{ Key "else" l }
 ELSEIF 		{ Key "elseif" l }
-- ELSEWHERE 		{ Key "elsewhere" l }
 END 			{ Key "end" l }
 ENDIF			{ Key "endif" l }
 ENDDO			{ Key "enddo" l }
 ENDFILE                { Key "endfile" l }
-- ENTRY 		{ Key "entry" l }
 EQUIVALENCE 		{ Key "equivalence" l }
 EXIT 			{ Key "exit" l }
 EXTERNAL 		{ Key "external" l }
 FORALL 		{ Key "forall" l }
 FOREACH		{ Key "foreach" l }
-- FORMAT 		{ Key "format" l }
 FUNCTION 		{ Key "function" l }
 GOTO 			{ Key "goto" l }
 IOLENGTH               { Key "iolength" l }
 IF 			{ Key "if" l }
 IMPLICIT 		{ Key "implicit" l }
 IN 			{ Key "in" l }
 INCLUDE		{ Key "include" l }
 INOUT 			{ Key "inout" l }
 INTEGER 		{ Key "integer" l }
 INTENT 		{ Key "intent" l }
 INTERFACE 		{ Key "interface" l }
 INTRINSIC 		{ Key "intrinsic" l }
 INQUIRE 		{ Key "inquire" l }
 KIND 			{ Key "kind" l }
 LEN 			{ Key "len" l }
 LOGICAL 		{ Key "logical" l }
 MODULE 		{ Key "module" l }
 NAMELIST 		{ Key "namelist" l }
 NONE 			{ Key "none" l }
 NULLIFY 		{ Key "nullify" l }
 NULL 			{ Key "null" l }
-- ONLY 		{ Key "only" l }
 OPEN 			{ Key "open" l }
 OPERATOR 		{ Key "operator" l }
 OPTIONAL 		{ Key "optional" l }
 OUT 			{ Key "out" l }
 PARAMETER 		{ Key "parameter" l }
-- PAUSE 		{ Key "pause" l }
 POINTER 		{ Key "pointer" l }
-- PRECISION 		{ Key "precision" l }
 PRINT 			{ Key "print" l }
 PRIVATE 		{ Key "private" l }
 PROCEDURE 		{ Key "procedure" l }
 PROGRAM 		{ Key "program" l }
 PURE 			{ Key "pure" l }
 PUBLIC 		{ Key "public" l }
 REAL 			{ Key "real" l }
 READ 			{ Key "read" l }
 RECURSIVE 		{ Key "recursive" l }
 RESULT 		{ Key "result" l }
 RETURN 		{ Key "return" l }
 REWIND 		{ Key "rewind" l }
 SAVE 			{ Key "save" l }
-- SELECT 		{ Key "select" l }
 SEQUENCE 		{ Key "sequence" l }
-- SIZE 		{ Key "size" l }
 SOMETYPE               { Key "sometype" l }
 SQRT			{ Key "sqrt" l }
 STAT 			{ Key "stat" l }
 STOP			{ Key "stop" l }
 STR                    { StrConst $$ l }
 SUBROUTINE 		{ Key "subroutine" l }
 TARGET 		{ Key "target" l }
-- TO 			{ Key "to" l }
 THEN 			{ Key "then" l }
 TYPE 			{ Key "type" l }
-- UNFORMATED 		{ Key "unformatted" l }
 USE 			{ Key "use" l }
 VOLATILE 		{ Key "volatile" l }
 WHERE 			{ Key "where" l }
 WRITE 			{ Key "write" l }
 ID                     { ID $$ l }
 NUM                    { Num $$ l }
 TEXT                   { Text $$ l }
%%

executable_program :: { [Program Annotation0] }
executable_program
  : program_unit_list                             { $1 }
    
program_unit_list :: { [Program Annotation0] }
program_unit_list
  : program_unit_list newline0 program_unit       { $1++[$3] }
  | {- empty -}                                   { [] }

program_unit :: { Program Annotation0 }
program_unit
  : main_program                                  { $1 }
  | external_subprogram                           { $1 }
  | module                                        { $1 }
  | block_data                                    { $1 }

plist :: { [String] }
plist 
  : plist ',' id2                                  { $1++[$3] }
  | id2                                            { [$1] }

vlist :: { [Expr Annotation0] }
vlist 
  : variable ',' vlist                             { $1:$3 }
  | variable                                       { [$1] }

newline :: {}
newline : '\n' newline {}
        | '\n'         {}

newline0 :: {}
newline0 : newline    {} 
        | {- empty -} {}

main_program :: { Program Annotation0 }
main_program
  : program_stmt use_stmt_list implicit_part specification_part_top execution_part module_subprogram_part end_program_stmt newline0
		{% do { s <- srcSpan (fst $ gcopoint $1);
		        name <- cmpNames (fst $1) $7 "program";
		        return (Main s name (snd $1) (Block s $2 $3 $4 $5) $6); } }

program_stmt :: { (SubName Annotation0, Arg Annotation0) }
program_stmt
  : PROGRAM subname args_p newline   { ($2, $3) }
  | PROGRAM subname        newline   {% srcSpan' $1 >>= (\l -> ($2, (Arg l (NullArg l)))) } 

end_program_stmt :: { String }
end_program_stmt
  : END PROGRAM id2   { $3 }
  | END PROGRAM       { "" }
  | END               { "" }

implicit_part :: { Implicit Annotation0 }
implicit_part : IMPLICIT NONE newline {% srcSpan' $1 >>= ImplicitNone }
              | {- empty -}           {% srcSpanNull >>= ImplicitNull }

--args
--  : args ',' id2                                   { }
--  | args                                          { }
--end_program_stmt :: { String }
--  : END                                           { "" }
--  | END PROGRAM                                   { "" }
--  | END PROGRAM id2                                { $3 }


external_subprogram :: { Program Annotation0}
external_subprogram
  : function_subprogram                         { $1 }
  | subroutine_subprogram                       { $1 } 

subroutine_subprogram :: { Program Annotation0 }
subroutine_subprogram 
  : subroutine_stmt use_stmt_list implicit_part specification_part_top execution_part end_subroutine_stmt newline0
  {% do { s <- srcSpan (fst $ gcopoint $1);
          name <- cmpNames (fst3 $1) $6 "subroutine";
          return (Sub s (trd3 $1) name (snd3 $1) (Block s $2 $3 $4 $5)); } }

end_subroutine_stmt :: { String }
end_subroutine_stmt
  : END SUBROUTINE id2            { $3 }
  | END SUBROUTINE                { "" }
  | END                           { "" }

end_function_stmt :: { String }
end_function_stmt
  : END FUNCTION id2                     { $3 }
  | END FUNCTION                         { "" }
  | END                                  { "" }

function_subprogram :: { Program }
function_subprogram
  : function_stmt use_stmt_list implicit_part specification_part_top execution_part end_function_stmt newline0
                {% cmpNames (fst3 $1) $6 "function" >>= \name -> return ((Function (trd3 $1) name (snd3 $1)
										      (Block $2 $3 $4 $5))) }

block_data :: { Program }
block_data
  : block_data_stmt use_stmt_list implicit_part specification_part_top end_block_data_stmt      {% cmpNames $1 $5 "block data" >>= \name -> return ((BlockData name $2 $3 $4)) }
  
block_data_stmt :: { SubName }
block_data_stmt
  : BLOCK DATA subname                     { $3 } 
  | BLOCK DATA                             { NullSubName } 

end_block_data_stmt :: { String }
end_block_data_stmt
  : END BLOCK DATA id2                            { $4 }
  | END BLOCK DATA                                { "" }
  | END                                           { "" }
  
module :: { Program }
module
  : module_stmt use_stmt_list implicit_part specification_part_top module_subprogram_part end_module_stmt { % cmpNames $1 $6  "module" >>= \name -> return (Module name $2 $3 $4 $5) }

module_stmt :: { SubName }
module_stmt
  : MODULE subname newline                    { $2 } 

end_module_stmt :: { String }
end_module_stmt
  : END MODULE id2                            { $3 }
  | END MODULE                                { "" }
  | END                                       { "" }

module_subprogram_part :: { [Program] }
module_subprogram_part
  : CONTAINS newline internal_subprogram_list { $3 }
| {- empty -}                                 { [] } 
  
internal_subprogram_list :: { [Program] }
internal_subprogram_list
  : internal_subprogram_list internal_subprogram newline0 { $1++[$2] } 
  | {- empty -}                                           { [] }
  
internal_subprogram :: { Program }
internal_subprogram
  : subroutine_subprogram                           { $1 }
  | function_subprogram                             { $1 }
  
use_stmt_list :: { [String] }
use_stmt_list
  : use_stmt_list use_stmt  { $2:$1 }
 | {- empty -}  	    { [] }

use_stmt :: { String }
use_stmt
  : USE id2 newline { $2 }
  
-- [DO: Allows the specification part of a module to be empty]
specification_part_top :: { Decl }
specification_part_top
   : specification_part   { $1 }
   |  {- empty -}         { NullDecl }

specification_part :: { Decl }
specification_part
  : declaration_construct_l specification_part { (DSeq $1 $2) }
  | declaration_construct_l                    { $1 }
  

declaration_construct_l :: { Decl }
declaration_construct_l
  : declaration_construct_p newline { $1 }

declaration_construct_p :: { Decl }
declaration_construct_p
  : declaration_construct                         { $1 }
  | specification_stmt                            { $1 }
  | derived_type_def                              { $1 }
  | TEXT					  { TextDecl $1 }

declaration_construct :: { Decl }
declaration_construct
  : type_spec_p attr_spec_list '::' entity_decl_list  { if isEmpty (fst $2) 
                                                        then Decl $4 ((BaseType (fst3 $1) (snd $2) (snd3 $1) (trd3 $1)))
							else Decl $4 ((ArrayT   (fst $2) (fst3 $1) (snd $2) (snd3 $1) (trd3 $1))) }
  | type_spec_p attr_spec_list      entity_decl_list  { if isEmpty (fst $2) 
                                                        then Decl $3 ((BaseType (fst3 $1) (snd $2) (snd3 $1) (trd3 $1)))
							else Decl $3 ((ArrayT   (fst $2) (fst3 $1) (snd $2) (snd3 $1) (trd3 $1))) }
  | interface_block				      { $1 }
  | include_stmt { $1 }

attr_spec_list :: {([(Expr,Expr)],[Attr])}
attr_spec_list
  : attr_spec_list ',' attr_spec                  { (fst $1++fst $3,snd $1++snd $3) }
  | {- empty -}                                   { ([],[]) }

entity_decl_list :: { [(Expr,Expr)] }
entity_decl_list
  : entity_decl_list ',' entity_decl              { $1++[$3] }
  | entity_decl                                   { [$1] }

entity_decl :: { (Expr,Expr) }
entity_decl
  : object_name '=' expr      { (Var [(VarName $1,[])], $3) }
  | variable                  { ($1, ne) }   -- TODO too general need to eleminate ability to parse v%u type vars
--  | function_name [ '*' char_length ]

object_name :: { String }
object_name
  : id2                                            { $1 }

type_spec_p :: { (BaseType,Expr,Expr) }
type_spec_p
  : type_spec                                     { (fst3 $1, snd3 $1, trd3 $1) }

type_spec :: { (BaseType,Expr,Expr) }
type_spec
  : INTEGER kind_selector                         { (Integer,$2,ne) }
  | INTEGER '*' length_value                      { (Integer,$3,ne) }
  | INTEGER                                       { (Integer,(ne),ne) }
  | REAL kind_selector                            { (Real,$2,ne) }
  | REAL '*' length_value                         { (Real,$3,ne) }
  | REAL                                          { (Real,(ne),ne) }
  | SOMETYPE                                      { (SomeType,(ne),ne) }
--  | DOUBLE PRECISION kind_selector                { (Double,$3,ne) }
--  | DOUBLE PRECISION '*' length_value             { (Double,$4,ne) }
--  | DOUBLE PRECISION                              { (Double,ne,ne) }
  | COMPLEX kind_selector                         { (Complex,$2,ne) }
  | COMPLEX '*' length_value                      { (Complex,$3,ne) }
  | COMPLEX                                       { (Complex,ne,ne) }
  | CHARACTER char_selector                       { (Character,snd $2, fst $2) }
  | CHARACTER                                     { (Character,ne,ne) }
  | LOGICAL kind_selector                         { (Logical,$2,ne) }
  | LOGICAL '*' length_value                      { (Logical,$3,ne) }
  | LOGICAL                                       { (Logical,ne,ne) }
  | TYPE '(' type_name ')'                          { (DerivedType $3,ne,ne) }
--  | POINTER '(' pointer_name ',' pointee_name ['(' array_spec ')' ] ')'
--[',' '(' pointer_name ',' pointee_name ['(' array_spec ')' ] ')' ] ...

kind_selector :: { Expr }
  : '(' KIND '=' expr ')'                         { $4 }
  | '(' expr ')'                                  { $2 }

char_selector :: { (Expr,Expr) }  -- (LEN, KIND)
char_selector 
: length_selector                                         { ($1,ne) }
| '(' LEN '=' char_len_param_value ',' KIND '=' expr ')'  { ($4,$8) }
| '(' char_len_param_value ',' KIND '=' expr ')'          { ($2,$6) }
| '(' char_len_param_value ',' expr ')'                   { ($2,ne) }
| '(' KIND '=' expr ',' LEN '=' char_len_param_value ')'  { ($8,$4) }
| '(' KIND '=' expr ')'                                   { (ne,$4) }

length_selector :: { Expr }
length_selector 
: '(' LEN '=' char_len_param_value ')'                                    { $4 }
| '(' char_len_param_value ')'                                            { $2 }

char_len_param_value :: { Expr }
char_len_param_value
  : specification_expr                                     { $1 }
  | '*'                                                    { (Con "*") }

length_value :: { Expr }
length_value
  : NUM                                           { (Con $1) }

dim_spec :: { [(Expr,Expr)] }
dim_spec
  : DIMENSION '(' array_spec ')' { $3 }
  | DIMENSION '(' ')'            { [] }  -- modified by Zhe on 11/14/2004

attr_spec :: { ([(Expr,Expr)],[Attr]) }
attr_spec
  : dim_spec                                       { ($1,[]) }
  | PARAMETER                                      { ([],[Parameter]) }
  | access_spec                                    { ([],[$1]) }
  | ALLOCATABLE                                    { ([],[Allocatable]) }
  | EXTERNAL                                       { ([],[External]) }
  | INTENT '(' intent_spec ')'                     { ([],[Intent $3]) }
  | INTRINSIC                                      { ([],[Intrinsic]) }
  | OPTIONAL                                       { ([],[Optional]) }
  | POINTER                                        { ([],[Pointer]) }
  | SAVE                                           { ([],[Save]) }
  | TARGET                                         { ([],[Target]) }
  | VOLATILE                                       { ([],[Volatile]) }

access_spec :: { Attr }
access_spec
  : PUBLIC            { Public }
  | PRIVATE           { Private }

array_spec :: { [(Expr,Expr)] }
array_spec
  : explicit_shape_spec_list                      { map expr2array_spec $1 }


explicit_shape_spec_list :: { [Expr] }
explicit_shape_spec_list
  : explicit_shape_spec_list ','  explicit_shape_spec {$1++[$3]}
  | explicit_shape_spec                               {[$1]}
explicit_shape_spec :: { Expr }
explicit_shape_spec
  : expr  { $1 } 
  | bound { $1 }

include_stmt :: { Decl }
  : INCLUDE STR               { Include (Con $2) }

specification_expr :: { Expr }
specification_expr
  : expr { $1 } 
intent_spec :: { IntentAttr }
intent_spec
  : IN            { In }
  | OUT           { Out }
  | INOUT         { InOut }

specification_stmt :: { Decl }
specification_stmt
  : access_stmt            { $1 }
--  | allocatable_stmt       { $1 }
  | common_stmt            { $1 }
  | data_stmt              { $1 }
--  | dimension_stmt         { $1 }
  | external_stmt          { $1 }
--  | intent_stmt            { $1 }
--  | intrinsic_stmt         { $1 }
  | namelist_stmt            { $1 }
--  | optional_stmt          { $1 }
--  | pointer_stmt           { $1 }
--  | save_stmt              { $1 }
--  | target_stmt            { $1 }

common_stmt :: { Decl }
 : COMMON '/' id2 '/' vlist  { Common (Just $3) $5 }
 | COMMON vlist              { Common Nothing $2 }


interface_block :: { Decl }
interface_block
  : interface_stmt interface_spec_list end_interface_stmt  { Interface $1 $2 }

interface_stmt :: { Maybe GSpec }
interface_stmt
  : INTERFACE generic_spec       { Just $2 }
  | INTERFACE                    { Nothing }
  
interface_spec_list :: { [InterfaceSpec] }
interface_spec_list
  : interface_spec_list interface_spec   { $1++[$2] }
  | interface_spec                       { [$1] }
  
interface_spec :: { InterfaceSpec }
interface_spec
  : interface_body               { $1 }
  | module_procedure_stmt        { $1 }
  
end_interface_stmt :: { Maybe GSpec }
end_interface_stmt
  : END INTERFACE generic_spec       { Just $3 }
  | END INTERFACE                    { Nothing }

interface_body :: { InterfaceSpec } 
interface_body
  : function_stmt   use_stmt_list implicit_part specification_part end_function_stmt    {% cmpNames (fst3 $1) $5 "interface declaration" >>= \name -> return (FunctionInterface   name (snd3 $1) $2 $3           $4) }
  | function_stmt                                                  end_function_stmt    {% cmpNames (fst3 $1) $2 "interface declaration" >>= \name -> return (FunctionInterface   name (snd3 $1) [] ImplicitNull (NullDecl)) }       
  | subroutine_stmt use_stmt_list implicit_part specification_part end_subroutine_stmt  {% cmpNames (fst3 $1) $5 "interface declaration" >>= \name -> return (SubroutineInterface name (snd3 $1) $2 $3           $4) }
  | subroutine_stmt                                                end_subroutine_stmt  {% cmpNames (fst3 $1) $2 "interface declaration" >>= \name -> return (SubroutineInterface name (snd3 $1) [] ImplicitNull (NullDecl)) }
  
module_procedure_stmt :: { InterfaceSpec }
module_procedure_stmt
  : MODULE PROCEDURE sub_name_list                   { ModuleProcedure $3 }

sub_name_list :: { [SubName] }
sub_name_list
  :               sub_name_list ',' sub_name     { $1++[$3] }
  |              		        	sub_name     { [$1] }

sub_name :: { SubName }
sub_name
  :  id2     { SubName $1 }

derived_type_def :: { Decl }
derived_type_def
  : derived_type_stmt private_sequence_stmt component_def_stmt_list end_type_stmt
  {% cmpNames (fst $1) $4 "derived type name" >>= \name -> return ((DerivedTypeDef name (snd $1) $2 $3)) }

derived_type_stmt :: { (SubName,[Attr]) }
derived_type_stmt
  : TYPE ',' access_spec  '::' type_name         { ($5,[$3]) }
  | TYPE                  '::' type_name         { ($3,[]) }
  | TYPE                       type_name         { ($2,[]) }

end_type_stmt :: { String }
end_type_stmt
  : END TYPE                { "" }
  | END TYPE id2            { $3 }


type_name :: { SubName }
type_name
  : id2                                 { SubName $1 } 

private_sequence_stmt :: { [Attr] }
private_sequence_stmt
  : PRIVATE SEQUENCE     { [Private,Sequence] }
  | SEQUENCE PRIVATE     { [Sequence,Private] }
  | PRIVATE              { [Private] }
  | SEQUENCE             { [Sequence] }
  | {- empty -}          { [] }
  
component_def_stmt_list :: { [Decl] }
component_def_stmt_list
  : component_def_stmt_list component_def_stmt     { $1++[$2] }
  | component_def_stmt                             { [$1] }

component_def_stmt :: { Decl }
component_def_stmt
  : type_spec_p component_attr_spec_list '::' entity_decl_list  { if isEmpty (fst $2) 
                                                        then Decl $4 ((BaseType (fst3 $1) (snd $2) (snd3 $1) (trd3 $1)))
							                            else Decl $4 ((ArrayT   (fst $2) (fst3 $1) (snd $2) (snd3 $1) (trd3 $1))) }

component_attr_spec_list :: {([(Expr,Expr)],[Attr])}
component_attr_spec_list
  : component_attr_spec_list ',' component_attr_spec       { (fst $1++fst $3,snd $1++snd $3) }
  | {- empty -}                                            { ([],[]) }

component_attr_spec :: { ([(Expr,Expr)],[Attr]) }
component_attr_spec
  :  POINTER                                        { ([],[Pointer]) }
  | dim_spec                                       { ($1,[]) }

access_stmt :: { Decl }
access_stmt
  : access_spec '::' access_id_list  { (AccessStmt $1 $3) }
  | access_spec access_id_list       { (AccessStmt $1 $2) }
  | access_spec                      { (AccessStmt $1 []) }
   
access_id_list :: { [GSpec] }
access_id_list
  : access_id_list ',' access_id     { $1++[$3] }
  | access_id                        { [$1] }

access_id :: { GSpec }
access_id 
  : generic_spec                     { $1 }
  
generic_spec :: { GSpec }
generic_spec
: id2					{ GName (Var [(VarName $1,[])]) } 
  | OPERATOR '(' defined_operator ')'   { GOper $3 }
  | ASSIGNMENT '(' '=' ')'              { GAssg  }
  
data_stmt :: { Decl }
data_stmt
  : DATA data_stmt_set_list				{ (Data $2) }
  
data_stmt_set_list :: { [(Expr,Expr)] }
data_stmt_set_list
  : data_stmt_set_list ',' data_stmt_set	{ $1++[$3] }
  | data_stmt_set							{ [$1] }
  
data_stmt_set :: { (Expr,Expr) }
data_stmt_set
  : data_stmt_object_list '/' data_stmt_value_list '/'		{ ($1,$3) }

data_stmt_object_list :: { Expr }
data_stmt_object_list
  : data_stmt_object_list ',' data_stmt_object   	{ (ESeq $1 $3) }
  | data_stmt_object								{ $1 }

data_stmt_object :: { Expr }
data_stmt_object
  : variable 			{ $1 }
  

data_stmt_value_list :: { Expr }
data_stmt_value_list
  : data_stmt_value_list ',' data_stmt_value	{ (ESeq $1 $3) }
  | data_stmt_value								{ $1 }

data_stmt_value :: { Expr }
data_stmt_value
  : primary			{ $1 }
  
  
external_stmt :: { Decl }
external_stmt
  : EXTERNAL '::' name_list  { (ExternalStmt $3) }
  | EXTERNAL      name_list  { (ExternalStmt $2) }
  
name_list :: { [String] }
name_list
  : name_list ',' id2          { $1++[$3] }
  | id2                        { [$1] }

id2 :: { String } -- hack len
id2 : ID { $1 }
    | LEN { "len" }
	
defined_operator :: { BinOp }
defined_operator
--  : defined_binary_op
--  | defined_unary_op
  : intrinsic_operator { $1 }

intrinsic_operator :: { BinOp }
intrinsic_operator
  : '**'        { Power }
  | '*'         { Mul }
  | '+'         { Plus }
  | '//'        { Concat }
  | rel_op      { $1 }
--  | '.NOT.'     { Not }
  | '.AND.'     { And }
  | '.OR.'      { Or } 
--  | equiv_op    { 



namelist_stmt :: { Decl }
namelist_stmt
  : NAMELIST namelist_list                                    {  (Namelist $2) }
  
namelist_list :: { [(Expr,[Expr])] }
namelist_list
  : namelist_list ',' '/' constant_p '/' namelist_group_object_list   { $1++[($4,$6)] }
  | '/' constant_p '/' namelist_group_object_list                     { [($2,$4)] }

namelist_group_object_list :: { [Expr] }
namelist_group_object_list
  : namelist_group_object_list ',' constant_p    { $1++[$3] }
  | constant_p                                     { [$1] }
  
subroutine_stmt :: { (SubName,Arg,Maybe BaseType) }
subroutine_stmt
  : SUBROUTINE subname args_p        newline { ($2,$3,Nothing) }
  | prefix SUBROUTINE subname args_p newline { ($3,$4,Just (fst3 $1)) }
  
function_stmt :: { (SubName,Arg,Maybe BaseType) }
function_stmt
  : prefix FUNCTION subname args_p RESULT '(' id2 ')' newline { ($3,$4,Just (fst3 $1)) }
  | prefix FUNCTION subname args_p                    newline { ($3,$4,Just (fst3 $1)) }
  | FUNCTION subname args_p RESULT '(' id2 ')'        newline { ($2,$3,Nothing) }
  | FUNCTION subname args_p                           newline { ($2,$3,Nothing) }
  
subname :: { SubName }
subname
  : id2	   { SubName $1 }
  
prefix :: { (BaseType, Expr, Expr) }
prefix
  : type_spec  { $1 }
  | RECURSIVE  { (Recursive,ne,ne) }
  | PURE       { (Pure,ne,ne) }
  | ELEMENTAL  { (Elemental,ne,ne) }

args_p :: { Arg }
args_p
  : '(' dummy_arg_list ')'                        { $2 }

dummy_arg_list :: { Arg }
dummy_arg_list
  : dummy_arg_list2                               { Arg $1 }
  | {- empty -}                                   { Arg NullArg }

dummy_arg_list2 :: { ArgName } 
dummy_arg_list2
  : dummy_arg_list2 ',' dummy_arg                 { ASeq $1 $3 }
  | dummy_arg                                     { $1 }

dummy_arg :: { ArgName }
dummy_arg
  : dummy_arg_name                                { ArgName $1 }
  | '*'                                           { ArgName "*" }
  
dummy_arg_name :: { String }
dummy_arg_name 
   : id2                                          { $1 }

--end_subroutine_stmt
--  : END SUBROUTINE

assignment_stmt :: { Fortran }
assignment_stmt
  : variable '=' expr                                 { (Assg $1 $3) }
 | ID '(' section_subscript_list ')' '=' expr         { (Assg (Var [(VarName $1, $3)]) $6) }


-- moved up to assignment_stmt
variable :: { Expr }
variable
  : subobject                                  { $1 }

subobject :: { Expr }
subobject
  : part_ref                                   { $1 }

part_ref :: { Expr }
part_ref
  : scalar_variable_name_list                  { Var $1 }

scalar_variable_name :: { (VarName,[Expr]) }
scalar_variable_name
  : id2	'(' section_subscript_list ')'                  { (VarName $1,$3) }
  | id2 '(' ')'                                         { (VarName $1,[ne]) }
  | id2                                                 { (VarName $1,[]) }
  
scalar_variable_name_list :: { [(VarName,[Expr])] }
scalar_variable_name_list
  : scalar_variable_name_list '%' scalar_variable_name    { $1++[$3] }
  | scalar_variable_name                                  { [$1] }

--part_name :: { VarName }
--  : ID                                            { VarName $1 }

-- bound comes through int_expr
subscript :: { Expr }
subscript
  : int_expr                                      { $1 }
  | bound                                         { $1 }
bound :: { Expr }
bound
  : expr ':' expr                               { (Bound $1 $3) }
  | expr ':'                                    { (Bound $1 ne)}
  | ':' expr                                    { (Bound ne $2) }
--  | ':'                                         { (Bound ne ne) }

section_subscript_list :: { [Expr] }
section_subscript_list
  : section_subscript_list ',' section_subscript  { $1++[$3] }
  | section_subscript                             { [$1] }
  
section_subscript :: { Expr }
section_subscript
  : subscript                                     { $1 }
  | id2 '=' expr									  { (AssgExpr $1 $3) }
--  | subscript_triplet
--  | vector_subscript                              { $1 }

--subscript_triplet
--subscript_triplet
--  : [ subscript ] ':' [ subscript ] [ ':' stride ]

stride :: { Expr }
stride 
  : int_expr                                      { $1 }

--vector_subscript :: { Expr }
--vector_subscript
--  : int_expr                                      { $1 }



expr :: { Expr }
expr
  : level_5_expr                                       { $1 }


level_5_expr :: { Expr }
level_5_expr
  : equiv_operand                                      { $1 }

equiv_operand :: { Expr }
equiv_operand
  : equiv_operand '.OR.' or_operand                    { Bin Or $1 $3 }
  | or_operand                                         { $1 }

or_operand :: { Expr }
or_operand
  : or_operand '.AND.' and_operand                     { Bin And $1 $3 }
  | and_operand                                        { $1 }


and_operand :: { Expr }
and_operand
  : level_4_expr                                       { $1 }

level_4_expr :: { Expr }
level_4_expr 
  : level_4_expr rel_op level_3_expr                   { Bin $2 $1 $3 }
  | level_3_expr                                       { $1 }


level_3_expr :: { Expr }
level_3_expr 
  : level_3_expr '//' level_2_expr                     { Bin Concat $1 $3 }
  | level_2_expr                                       { $1 }

level_2_expr :: { Expr }
level_2_expr 
  : level_2_expr '+' add_operand                       { Bin Plus $1 $3 }
  | level_2_expr '-' add_operand                       { Bin Minus $1 $3 }
  | add_operand                                        { $1 }

add_operand :: { Expr }
add_operand 
  : add_operand '*' mult_operand                       { (Bin Mul $1 $3) }
  | add_operand '/' mult_operand                       { (Bin Div $1 $3) }
  | mult_operand                                       { $1 }

mult_operand :: { Expr }
mult_operand 
  : level_1_expr '**' mult_operand                     { (Bin Power $1 $3) }
  | level_1_expr                                       { $1 }

level_1_expr :: { Expr }
level_1_expr 
  : '-' primary                                        { (Unary UMinus $2) }
  | '.NOT.' primary                                    { (Unary Not $2) }
  | primary                                            { $1 }

primary :: { Expr }
primary 
  : constant                                    { $1 }
  | variable                                    { $1 }
  | array_constructor                           { $1 }
  | '(' expr ')'                                { $2 }
  | SQRT '(' expr ')'				{ (Sqrt $3) }
  | ':'                                         { (Bound ne ne) }
-- causes problems
--  |  function_reference                          { $1 }

fields :: { [String] }
fields
  : fields '.' id2                              { $1++[$3] }
  | id2                                         { [$1] }
  
array_constructor :: { Expr }
array_constructor
  : '(/' expr_list '/)'           { (ArrayCon $2) } 

expr_list :: { [Expr] }
expr_list
  : expr_list ',' expr          { $1++[$3] }
  | expr                        { [$1] }
  
constant_p :: { Expr }
constant_p
  : constant_p2                        { $1 }
 
constant_p2 :: { Expr }
constant_p2
  : id2             { (Var [(VarName $1,[])]) }
  
constant :: { Expr }
constant 
  : literal_constant                             { $1 }

literal_constant :: { Expr }
literal_constant 
  : NUM                                          { Con $1 } -- {% (srcSpan l) >>= (\b -> Con b $1) }
  | STR						 { (ConS $1) }
  | logical_literal_constant			 { $1 }

logical_literal_constant :: { Expr }
logical_literal_constant 
  : '.TRUE.'                          { (Con  ".TRUE.") }
  | '.FALSE.'                         { (Con  ".FALSE.") }


rel_op :: { BinOp }
  : '=='                           { RelEQ }
  | '/='                           { RelNE }
  | '<'                            { RelLT }
  | '<='                           { RelLE }
  | '>'                            { RelGT }
  | '>='                           { RelGE }

int_expr :: { Expr }
int_expr
  : expr                                         { $1 }

do_variable :: { VarName } 
do_variable
  : id2                                           { VarName $1 }

do_construct :: { Fortran }
do_construct
  : block_do_construct                           { $1 }

block_do_construct :: { Fortran } 
block_do_construct                         -- For  VarName Expr Expr Fortran
  : do_stmt do_block end_do  { for (fst4 $1) (snd4 $1) (trd4 $1) (frh4 $1) $2 }

do_stmt :: { (VarName,Expr,Expr,Expr) }
do_stmt
  : nonlabel_do_stmt newline        { $1 }

nonlabel_do_stmt :: { (VarName,Expr,Expr,Expr) }
nonlabel_do_stmt
  : DO loop_control                  { $2 }

loop_control :: { (VarName,Expr,Expr,Expr) }
loop_control
  : do_variable '=' int_expr ','  int_expr loop_control2  { ($1,$3,$5,$6) }
--  | int_expr comma_int_expr_opt comma_opt WHILE '(' scalar_logical_expr ')'

loop_control2 :: { Expr }
loop_control2
  : ',' int_expr                                  { $2 }
  | {- empty -}                                   { (Con "1") }


--comma_int_expr_opt :: { FExpr }
--comma_int_expr_opt
--  : ',' int_expr                                  {  }
--  | {}                                            {  }

--comma_opt
--  : ','
--  | {}

do_block :: { Fortran }
do_block
  : block                                         { $1 }

end_do :: { }
end_do
  : END DO {} 
  | ENDDO  {} 

block :: { Fortran }
block
  : executable_construct_list                       { $1 }
  | {- empty -}                                     { NullStmt }
 
execution_part :: { Fortran }
execution_part 
  : executable_construct_list        { $1 }
| {- empty -}                        { NullStmt }

executable_construct_list :: { Fortran }
executable_construct_list
: executable_construct_list executable_construct_list  { (FSeq $1 $2) }
| executable_construct  newline                        { $1 }

executable_construct :: { Fortran }
executable_construct
  : NUM executable_construct                      { Label $1 $2 }
--  | case_construct
  | do_construct                                  { $1 }
  | if_construct                                  { $1 }
  | action_stmt                                   { $1 }
--  | forall_construct
--  | where_construct
 

equivalence_stmt :: { Fortran }
equivalence_stmt 
  : EQUIVALENCE '(' vlist ')'                     { Equivalence $3 }

action_stmt :: { Fortran }
action_stmt
  : allocate_stmt                                 { $1 }
 | assignment_stmt                               {% getSrcLoc >>= (\p -> getCurrentPos >>= (\p' -> (show (p, p')) `trace` return $1)) }
  | backspace_stmt                                { $1 }
  | call_stmt                                     { $1 }
  | close_stmt                                    { $1 }
  | continue_stmt                                 { $1 }
  | cycle_stmt                                    { $1 }
  | deallocate_stmt                               { $1 }
  | endfile_stmt                                  { $1 }
  | equivalence_stmt                              { $1 }
--  | end_function_stmt
--  | end_program_stmt
--  | end_subroutine_stmt
  | exit_stmt                                     { $1 }
  | forall_stmt                                   { $1 }
  | goto_stmt                                     { $1 }
  | if_stmt                                       { $1 }
  | inquire_stmt                                  { $1 }
  | nullify_stmt                                  { $1 }
  | open_stmt                                     { $1 }
  | pointer_assignment_stmt                       { $1 }
  | print_stmt                                    { $1 }
  | read_stmt                                     { $1 }
  | return_stmt                                   { $1 }
  | rewind_stmt                                   { $1 }
  | stop_stmt                                     { $1 }
  | where_stmt                                    { $1 }
  | write_stmt                                    { $1 }
  | TEXT				          { (TextStmt $1) }

call_stmt :: { Fortran }
call_stmt
  : CALL call_name '(' actual_arg_spec_list ')'                      { (Call $2 (ArgList $4)) }
  | CALL call_name '(' ')'                                           { (Call $2 (ArgList (ne))) }
  | CALL call_name                                                   { (Call $2 (ArgList (ne))) }

call_name :: { Expr }
call_name
  :                   ID               {             ((Var [(VarName $1,[])]))  }  

actual_arg_spec_list :: { Expr }
actual_arg_spec_list
  : actual_arg_spec_list ',' actual_arg_spec      { (ESeq $1 $3) }
  | actual_arg_spec                               { $1 }

actual_arg_spec :: { Expr }
actual_arg_spec
  : id2 '=' actual_arg                             { (AssgExpr $1 $3) }
  | actual_arg                                    { $1 }

actual_arg  :: { Expr }
actual_arg
  : expr                                          { $1 }
--  | variable
--  | procedure_name
--  | alt_return_spec

else_if_list :: { [(Expr,Fortran)]  }
else_if_list
  : else_if_list else_if_then_stmt block   { $1++[($2,$3)] }
  | {- empty -}                            { [] }

else_if_stmt :: { Expr }
else_if_stmt
  : ELSE if_then_stmt             { $2 }

if_then_stmt :: { Expr }
if_then_stmt 
  : IF '(' logical_expr ')' THEN newline              { $3 }

else_if_then_stmt :: { Expr }
else_if_then_stmt 
  : ELSEIF '(' logical_expr ')' THEN newline          { $3 }


--if_rest :: { ([(Expr,Fortran)],Maybe Fortran) }
--: ELSE if_then_stmt block if_rest      { (($2,$3):(fst $4),snd $4) }
--| ELSE block END IF                   { ([],Just $2) }
--| END IF                              { ([],Nothing) }

if_construct :: { Fortran }
if_construct
 : if_then_stmt block end_if_stmt                            { (If $1 $2 [] Nothing) }
--| if_then_stmt block ELSE block end_if_stmt                { (If $1 $2 [] (Just $4)) }

| if_then_stmt block else_if_list end_if_stmt                { (If $1 $2 $3 Nothing) }
| if_then_stmt block else_if_list ELSE newline block end_if_stmt     { (If $1 $2 $3 (Just $6)) }


--: if_then_stmt block if_rest				  { (If $1 $2 (fst $3) (snd $3)) }
--: if_then_stmt block else_if_list END IF                { (If $1 $2 $3 Nothing) }
--| if_then_stmt block else_if_list ELSE block END IF     { (If $1 $2 $3 (Just $5)) }
--| if_then_stmt block END IF                             { (If $1 $2 [] Nothing) }
--| if_then_stmt block ELSE block END IF                  { (If $1 $2 [] (Just $4)) }

--  : if_then_stmt block 
----    else_if_list 
--    else_opt 
--    END IF                                        { (If $1 $2 $3) }

end_if_stmt  :: {}
end_if_stmt  : END IF  { }
             | ENDIF   { } 


logical_expr :: { Expr }
logical_expr
  : expr                                          { $1 }

allocate_stmt :: { Fortran }
allocate_stmt
  : ALLOCATE '(' allocation_list ',' STAT '=' variable ')'    { (Allocate $3 $7) }
  | ALLOCATE '(' allocation_list ')'                         { (Allocate $3 ne) }
allocation_list :: { Expr }
allocation_list
  : allocation_list ',' allocation                    { (ESeq $1 $3) }
  | allocation                                        { $1 }
  | {- empty -}                                       { NullExpr }

allocate_object_list :: { [Expr] }
allocate_object_list
  : allocate_object_list ',' allocate_object      { $1++[$3] }
  | allocate_object                               { [$1] }
allocate_object :: { Expr }
allocate_object
  : scalar_variable_name_list                           { (Var $1) }

allocate_shape_spec_list :: { [Expr] }
allocate_shape_spec_list
  : allocate_shape_spec_list ',' allocate_shape_spec    { $1++[$3] }
  | allocate_shape_spec                                 { [$1] }
allocate_shape_spec :: { Expr }
allocate_shape_spec
  : expr   { $1 }
  | bound  { $1 }
allocation :: { Expr }
allocation
  : allocation_var_list2                          { $1 }

allocation_var_list2 :: { Expr }
allocation_var_list2
  : allocation_var_list                          {(Var $1) }

allocation_var_list :: { [(VarName,[Expr])] }
allocation_var_list
  : allocation_var_list '%' allocation_var      { $1++[$3]  }
  | allocation_var                              { [$1] }

allocation_var :: { (VarName,[Expr]) }
allocation_var
  : id2 '(' allocate_shape_spec_list ')'         { (VarName $1, $3) }
  | id2                                          { (VarName $1, []) }

backspace_stmt :: { Fortran }
backspace_stmt
  : BACKSPACE expr                                { (Backspace [NoSpec $2]) }
  | BACKSPACE '(' position_spec_list ')'          { (Backspace $3) }
position_spec_list :: { [Spec] }
position_spec_list
  : position_spec_list ',' position_spec          { $1++[$3] }
  | position_spec                                 { [$1] }
position_spec :: { Spec }
position_spec
  : expr                                          { NoSpec $1 }
  | ID '=' expr                                   {% case (map (toLower) $1) of
                                                     "unit"   -> return (Unit    $3)
                                                     "iostat" -> return (IOStat  $3)
                                                     s           ->  parseError ("incorrect name in spec list: " ++ s) }
close_stmt :: { Fortran }
close_stmt
  : CLOSE '(' close_spec_list ')'                 { (Close $3) }
close_spec_list :: { [Spec] }
close_spec_list
  : close_spec_list ',' close_spec                { $1++[$3] }
  | close_spec                                    { [$1] }
close_spec :: { Spec }
close_spec
  : expr                                          { NoSpec $1 }
  | ID '=' expr                                   {% case (map (toLower) $1) of
                                                     "unit"   -> return (Unit   $3)
                                                     "iostat" -> return (IOStat $3)
                                                     "status" -> return (Status $3)
                                                     s            -> parseError ("incorrect name in spec list: " ++ s) }
--external_file_unit :: { Expr }
--external_file_unit
--  : expr                                          { $1 }

continue_stmt :: { Fortran }
continue_stmt
  : CONTINUE                                      { Continue }

cycle_stmt :: { Fortran }
cycle_stmt
  : CYCLE id2                                      { (Cycle $2) }
  | CYCLE                                         { (Cycle "") }

deallocate_stmt :: { Fortran }
deallocate_stmt
: DEALLOCATE '(' allocate_object_list ',' STAT '=' variable ')' { (Deallocate $3 $7) }
| DEALLOCATE '(' allocate_object_list ')'                            { (Deallocate $3 (ne)) }

endfile_stmt :: { Fortran }
endfile_stmt
  : ENDFILE expr                                  { (Endfile [NoSpec $2]) }
  | ENDFILE '(' position_spec_list ')'            { (Endfile $3)}

exit_stmt :: { Fortran }
exit_stmt
  : EXIT id2                                       { (Exit $2) }
  | EXIT                                          { (Exit "") }

forall_stmt :: { Fortran }
forall_stmt 
  : FORALL forall_header forall_assignment_stmt               { (Forall $2 $3) }
  | FORALL forall_header newline forall_assignment_stmt_list
                                forall_stmt_end               { (Forall $2 $4) }

forall_stmt_end :: {}
forall_stmt_end 
  : END FORALL       {}
 | {- empty -}       {}

forall_header :: { ([(String,Expr,Expr,Expr)],Expr) }
forall_header
  : '(' forall_triplet_spec_list ',' expr ')'     { ($2,$4) }
  | '(' forall_triplet_spec_list ')'              { ($2,ne) }
forall_triplet_spec_list :: { [(String,Expr,Expr,Expr)] }
forall_triplet_spec_list
  : forall_triplet_spec_list ',' forall_triplet_spec  { $1++[$3]}
  | forall_triplet_spec                               { [$1] }
forall_triplet_spec :: { (String,Expr,Expr,Expr) }
forall_triplet_spec
  : id2 '=' int_expr ':' int_expr ';' int_expr { ($1,$3,$5,$7) }
  | id2 '=' int_expr ':' int_expr              { ($1,$3,$5,ne) }

forall_assignment_stmt :: { Fortran }
forall_assignment_stmt
  : assignment_stmt                               { $1 }
  | pointer_assignment_stmt                       { $1 }

forall_assignment_stmt_l :: { Fortran }
forall_assignment_stmt_l
  : forall_assignment_stmt newline { $1 }

forall_assignment_stmt_list :: { Fortran }
forall_assignment_stmt_list 
  : forall_assignment_stmt_l forall_assignment_stmt_list { FSeq $1 $2 }
  | forall_assignment_stmt_l                             { $1 }


goto_stmt :: { Fortran }
goto_stmt
  : GOTO NUM                                      { (Goto $2) }

if_stmt :: { Fortran }
if_stmt
  : IF '(' logical_expr ')' action_stmt           { (If $3 $5 [] Nothing) }

inquire_stmt :: { Fortran }
inquire_stmt
  : INQUIRE '(' inquire_spec_list ')'                       { (Inquire $3 []) } 
  | INQUIRE '(' IOLENGTH '=' variable ')' output_item_list  { (Inquire [IOLength $5] $7) }
inquire_spec_list :: { [Spec] }
inquire_spec_list
  : inquire_spec_list ',' inquire_spec               { $1++[$3] }
  | inquire_spec                                 { [$1] }
inquire_spec :: { Spec }
inquire_spec
  : expr                                         { NoSpec $1 }
  | READ '=' variable                            { Read $3 }
  | WRITE '=' variable                           { WriteSp $3 }
  | ID '=' expr                                  {% case (map (toLower) $1) of
                                                    "unit"        -> return (Unit		 $3)
                                                    "file"        -> return (File		 $3)
                                                    "iostat"      -> return (IOStat      $3)
                                                    "exist"       -> return (Exist       $3)
                                                    "opened"      -> return (Opened      $3)
                                                    "number"      -> return (Number      $3)
                                                    "named"       -> return (Named       $3)
                                                    "name"        -> return (Name        $3)
                                                    "access"      -> return (Access      $3)
                                                    "sequential"  -> return (Sequential  $3)
                                                    "direct"      -> return (Direct      $3)
                                                    "form"        -> return (Form        $3)
                                                    "formatted"   -> return (Formatted   $3)
                                                    "unformatted" -> return (Unformatted $3)
                                                    "recl"        -> return (Recl        $3)
                                                    "nextrec"     -> return (NextRec     $3)
                                                    "blank"       -> return (Blank       $3)
                                                    "position"    -> return (Position    $3)
                                                    "action"      -> return (Action      $3)
                                                    "readwrite"   -> return (ReadWrite   $3)
                                                    "delim"       -> return (Delim       $3)
                                                    "pad"         -> return (Pad         $3)
                                                    s             -> parseError ("incorrect name in spec list: " ++ s) }
--io_implied_do
--io_implied_do
--  : '(' io_implied_do_object_list ',' io_implied_do_control ')'
--io_implied_do_object
--io_implied_do_object
--  : input_item
--  | output_item
--io_implied_do_control
--io_implied_do_control
--  : do_variable '=' scalar_int_expr ',' scalar_int_expr ',' scalar_int_expr
--  | do_variable '=' scalar_int_expr ',' scalar_int_expr
--file_name_expr
--file_name_expr
--  : scalar_char_expr



nullify_stmt :: { Fortran }
nullify_stmt
  : NULLIFY '(' pointer_object_list ')'           { (Nullify $3) }
pointer_object_list :: { [Expr] }
pointer_object_list
  : pointer_object_list ',' pointer_object            { $1++[$3] }
  | pointer_object                                { [$1] }
pointer_object :: { Expr }
pointer_object
--  : ID                                            { (Var [VarName $1] []) }
  : structure_component                           { $1 }
structure_component :: { Expr }
structure_component
  : part_ref                                      { $1 }

open_stmt :: { Fortran }
open_stmt
  : OPEN '(' connect_spec_list ')'                { (Open $3) }
connect_spec_list :: { [Spec] }
connect_spec_list
  : connect_spec_list ',' connect_spec                { $1++[$3] }
  | connect_spec                                  { [$1] }
connect_spec :: { Spec }
connect_spec
  : expr                                          { NoSpec $1 }
  | ID '=' expr                                 {% case (map (toLower) $1) of
                                                   "unit"     -> return (Unit $3)  
                                                   "iostat"   -> return (IOStat  $3)
                                                   "file"     -> return (File $3)
                                                   "status"   -> return (Status $3)
                                                   "access"   -> return (Access $3)
                                                   "form"     -> return (Form $3)
                                                   "recl"     -> return (Recl $3)
                                                   "blank"    -> return (Blank $3)
                                                   "position" -> return (Position $3)
                                                   "action"   -> return (Action $3)
                                                   "delim"    -> return (Delim $3)
                                                   "pad"      -> return (Pad $3)
                                                   s          -> parseError ("incorrect name in spec list: " ++ s) }
file_name_expr :: { Expr }
file_name_expr
  : scalar_char_expr                              { $1 }

scalar_char_expr :: { Expr }
scalar_char_expr
  : expr                                          { $1 }

scalar_int_expr :: { Expr }
scalar_int_expr
  : expr                                          { $1 }

pointer_assignment_stmt :: { Fortran }
pointer_assignment_stmt
  : pointer_object '=>' target                    { (PointerAssg $1 $3) }
target :: { Expr }
target
  : expr                                          { $1 }



print_stmt :: { Fortran }
print_stmt
  : PRINT format ',' output_item_list           { (Print $2 $4) }
  | PRINT format                                { (Print $2 []) }

-- also replaces io_unit
format :: { Expr }
format
  : expr                                          { $1 }
--  | literal_constant                              { (Con $1) } -- label
  | '*'                                           { (Var [(VarName "*",[])]) }
output_item_list :: { [Expr] }
output_item_list
  : output_item_list ','  output_item                  { $1++[$3] }
  | output_item                                   { [$1] }
output_item :: { Expr }
output_item
  : expr                                          { $1 }
--  | io_implied_do                                 { $1 }



read_stmt :: { Fortran }
read_stmt
  : READ '(' io_control_spec_list ')' input_item_list { (ReadS $3 $5) }
  | READ '(' io_control_spec_list ')'                 { (ReadS $3 []) }
--  | READ format ',' output_item_list                  { (ReadS [NoSpec $2] $4) }
--  | READ format                                       { (ReadS [NoSpec $2] []) }
io_control_spec_list :: { [Spec] }
io_control_spec_list
  : io_control_spec_list ',' io_control_spec      { $1++[$3] }
  | io_control_spec                               { [$1] }
-- (unit, fmt = format), (rec, advance = expr), (nml, iostat, id = var), (err, end, eor = label)
io_control_spec :: { Spec } 
io_control_spec
  : format                                        { NoSpec $1 }
  | END '=' label                                 { End $3 }
  | ID '=' format                                 {% case (map (toLower) $1) of
                                                     "unit"    -> return (Unit $3)
                                                     "fmt"     -> return (FMT $3)
                                                     "rec"     -> return (Rec $3)
                                                     "advance" -> return (Advance $3)
                                                     "nml"     -> return (NML  $3)
                                                     "iostat"  -> return (IOStat  $3)
                                                     "size"    -> return (Size  $3)
                                                     "eor"     -> return (Eor $3)
                                                     s          -> parseError ("incorrect name in spec list: " ++ s) }
--  | namelist_group_name                           { NoSpec $1 }
input_item_list :: { [Expr] }
input_item_list
  : input_item_list ',' input_item                { $1++[$3] }
  | input_item                                    { [$1] }
input_item :: { Expr }
input_item
  : variable                                      { $1 }
--  | io_implied_do
--io_unit :: { Expr }
--io_unit
--  : expr                                          { $1 }
--  | '*'                                           { (Var [(VarName "*",[])]) }
--  | internal_file_unit                            { $1 }

label :: { Expr }
label
  : NUM                                           { (Con $1) }

--internal_file_unit :: { Expr }
--internal_file_unit
--  : default_char_variable                         { $1 }

--default_char_variable :: { Expr }
--default_char_variable
--  : variable                                      { $1 }
namelist_group_name :: { Expr }
namelist_group_name
  : variable                                      { $1 }


return_stmt :: { Fortran }
return_stmt
  : RETURN                                        { (Return (ne)) }
  | RETURN int_expr                               { (Return $2) }

scalar_default_int_variable :: { Expr }
scalar_default_int_variable
  : variable                                      { $1 }

scalar_default_char_expr :: { Expr }
scalar_default_char_expr
  : expr                                          { $1 }

rewind_stmt :: { Fortran }
rewind_stmt
  : REWIND expr                                  { (Rewind [NoSpec $2]) }
  | REWIND '(' position_spec_list ')'            { (Rewind $3) }



stop_stmt :: { Fortran }
stop_stmt
  : STOP stop_code                               { (Stop $2) }
  | STOP                                         { (Stop (ne)) }
stop_code :: { Expr }
stop_code
  : constant                                     { $1 }
  


where_stmt :: { Fortran }
where_stmt
  : WHERE '(' mask_expr ')' where_assignment_stmt { (Where $3 $5) }
where_assignment_stmt :: { Fortran }
where_assignment_stmt
  : assignment_stmt                              { $1 }
mask_expr :: { Expr }
mask_expr
  : logical_expr                                 { $1 }



write_stmt :: { Fortran }
write_stmt
  : WRITE '(' io_control_spec_list ')' output_item_list  { (Write $3 $5) }
  | WRITE '(' io_control_spec_list ')'                   { (Write $3 []) }


{

[annotateFrom| {Language.Fortran}

happyError :: P a
happyError = parseError "syntax error"

parseError :: String -> P a
parseError m = do srcloc <- getSrcLoc 
		  fail ("line " ++ show (srcLine srcloc) ++ " column " ++ show (srcColumn srcloc) ++ ": " ++ m ++ "\n")

tokenFollows s = case alexScan ('\0',s) 0 of
                    AlexEOF               -> "end of file"
                    AlexError  _          -> ""
                    AlexSkip  (_,t) len   -> tokenFollows t
                    AlexToken (_,t) len _ -> take len s

parse :: String -> [Program]
parse p = case (runParser parser p) of 
	    (ParseOk p)       -> p
            (ParseFailed l e) ->  error e

--parse :: String -> [Program]
--parse = clean . parser . fixdecls . scan

parseF :: String -> IO ()
parseF f = do s <- readFile f
              print (parse s)

--scanF :: String -> IO ()
--scanF f = do s <- readFile f
--             print (scan s)

fst3 (a,b,c) = a
snd3 (a,b,c) = b
trd3 (a,b,c) = c

fst4 (a,b,c,d) = a
snd4 (a,b,c,d) = b
trd4 (a,b,c,d) = c
frh4 (a,b,c,d) = d

cmpNames :: SubName -> String -> String -> P SubName
cmpNames x "" z                      = return x
cmpNames (SubName x) y z | x==y      = return (SubName x)
                         | otherwise = parseError (z ++ " name \""++x++"\" does not match \""++y++"\" in end " ++ z ++ " statement\n")
cmpNames s y z                       = parseError (z ++" names do not match\n")
					   
isEmpty :: [a] -> Bool
isEmpty [] = True
isEmpty _  = False

-- returns one var from allocation list all var names are part of var, all but last bound also
-- last bound is allocation bounds, var needs to convert bounds to exprs
fix_allocate :: [(VarName,[(Expr,Expr)])] -> (Expr,[(Expr,Expr)])
fix_allocate xs = (var,bound)
                where vs     = map (\(x,y) -> (x,map snd y)) (init xs)
                      var    = Var (vs++[(fst (last xs),[])])
                      bound  = snd (last xs)
					  
seqBound :: [(Expr,Expr)] -> Expr
seqBound [] = ne
seqBound [b] = toBound b
seqBound (b:bs) = (ESeq (toBound b) (seqBound bs))

toBound :: (Expr,Expr) -> Expr
toBound (NullExpr, e) = e
toBound (e,e') = (Bound e e')

expr2array_spec (Bound e e') = (e,e')
expr2array_spec e = (ne,e)

|]
}
