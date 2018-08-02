
'Help!

Namespace mx2

Class TryParseEx Extends Throwable
End

Class Parser

	Method New()
	End
	
	Method New( source:String,ppsyms:StringMap<String> )
		Self.New()
	
		_ppsyms=ppsyms
		
		_toker=New Toker( source )
		Bump()
	End	

	Method ParseFile:FileDecl( ident:String,srcPath:String,ppsyms:StringMap<String> )
		
		Local srcPath2:=srcPath,gpath:=""
		
		If Builder.opts.geninfo
			
			Local dir:=ExtractDir( srcPath )+".mx2/"
			Local name:=StripDir( srcPath )
			Local path:=dir+name
			
			'use tmp file ONLY if newer than real file.
			If GetFileType( path )=FileType.File And GetFileTime( path )>GetFileTime( srcPath ) srcPath2=path
				
			gpath=StripExt( path )+".geninfo"
		Endif
	
		_ppsyms=ppsyms
		
		_cc.Clear()
		_cc.Push( 1 )
		
		_fdecl=New FileDecl
		_fdecl.ident=ident
		_fdecl.path=srcPath
		_fdecl.gpath=gpath
		_fdecl.nmspace=""
		
		Local source:=LoadString( srcPath2 )
		_toker=New Toker( source )
		
		PNode.parsing=_fdecl

		Bump()
		CParseEol()
		
		_fdecl.members=ParseDecls( DECL_PUBLIC,True )
		
		If Not _fdecl.nmspace _fdecl.nmspace="default"
		
		_fdecl.usings=_usings.ToArray()
		_fdecl.imports=_imports.ToArray()
		_fdecl.reflects=_reflects.ToArray()
		_fdecl.errors=_errors.ToArray()
		_fdecl.endpos=EndPos
		
		PNode.parsing=Null
		
		Return _fdecl
	End
	
	'THROWS!
	Method ParseNamespaceIdent:String()
		Local ident:=ParseIdent()

		While CParse( "." )
			ident+="."+ParseIdent()
		Wend
		
		Return ident
	End
		
	'THROWS!
	Method ParseUsingIdent:String()
	
		If CParse( "*" ) Return "*"
		
		Local ident:=ParseIdent()

		While CParse( "." )
			If CParse( "*" ) Return ident+".*"
			If CParse( "." ) Return ident+".."
			ident+="."+ParseIdent()
		Wend
		
		Return ident
	End
	
	Method Meta:String()
	
		Return _meta
	End
	
	Method ParseMeta:String()
	
		If Not CParse( "[" ) Return ""
		
		Local meta:=""
		Repeat
		
			Local key:=ParseIdent()
			
			Parse( "=" )

			Local value:=""
			
			Select TokeType
			Case TOKE_INTLIT,TOKE_FLOATLIT
				value=Parse()
			Case TOKE_STRINGLIT
				value=DequoteMx2String( Parse() )
				If value.Contains( "~~~n" ) Error( "Invalid meta data value!" )
			Default
				Error( "Expecting literal meta value" )
			End
			
			If meta meta+="~~~n"
			meta+=key+"="+value
			
		Until Not CParse( "," )
			
		Parse( "]" )
		ParseEol()
		
		Return meta
	End
	
	Method ParseAccessFlags:Int( flags:Int,fileScope:Bool )
		
		flags&=~DECL_ACCESSMASK
		
		If fileScope flags&=~DECL_EXTERN
		
		If CParse( "public" )
			flags|=DECL_PUBLIC
		Else If CParse( "private" )
			flags|=DECL_PRIVATE
		Else If CParse( "protected" )
			If fileScope Error( "'Protected' can only be used in a class, struct or interface" )
			flags|=DECL_PROTECTED
			If CParse( "internal" ) 
				flags|=DECL_INTERNAL
			Endif
		Else If CParse( "internal" )
			flags|=DECL_INTERNAL|DECL_PUBLIC
		Else If CParse( "extern" )
			If Not fileScope Error( "'Extern' must appear at file scope" )
			flags|=DECL_EXTERN
			If CParse( "private" ) 
				flags|=DECL_PRIVATE
			Else If CParse( "internal" )
				flags|=DECL_INTERNAL|DECL_PUBLIC
			Else
				CParse( "public" )
				flags|=DECL_PUBLIC
			Endif
		Endif
		
		Return flags
	End
	
	Method ParseDecls:Decl[]( flags:Int,fileScope:Bool )
	
		Local decls:=New Stack<Decl>
		
		While Toke And Toke<>"end"
		
			Try
			
				Select Toke
				Case "namespace"
					If Not fileScope Or decls.Length Or _usings.Length Error( "'Namespace' must appear at the start of the file" )
					If _fdecl.nmspace Error( "Duplicate namespace declaration" )
					Bump()					
					_fdecl.docs=Docs()
					_fdecl.nmspace=ParseNamespaceIdent()
					ParseEol()
					Continue
				Case "using"
					If Not fileScope Or decls.Length Error( "Usings must appear before any declarations in a file" )
					Bump()
					_usings.Push( ParseUsingIdent() )
					ParseEol()
					Continue
				Case "public","private","protected","internal","extern"
					flags=ParseAccessFlags( flags,fileScope )
					ParseEol()
					Continue
				End
			
				_meta=ParseMeta()
				
				Select Toke
				Case "const"
					ParseVars( decls,flags )
				Case "global"
					ParseVars( decls,flags )
				Case "field"
					If flags & DECL_IFACEMEMBER Error( "Interfaces cannot have fields" )
					If flags & DECL_EXTENSION Error( "Type extensions cannot have fields" )
					If fileScope Error( "Fields may only be declared within a class or struct." )
					ParseVars( decls,flags )
				Case "local"
					Error( "Locals can only be declared in a statement block" )
				Case "alias"
					ParseAliases( decls,flags )
				Case "class"
					decls.Push( ParseClass( flags ) )
				Case "struct"
					decls.Push( ParseClass( flags ) )
				Case "interface"
					decls.Push( ParseClass( flags ) )
				Case "enum"
					decls.Push( ParseEnum( flags ) )
				Case "function"
					decls.Push( ParseFunc( flags ) )
				Case "method"
					If fileScope Error( "Methods can only be declared inside a class, struct or interface" )
					decls.Push( ParseFunc( flags ) )
				Case "operator"
					If fileScope Error( "Operators can only be declared inside a class, struct or interface" )
					decls.Push( ParseFunc( flags ) )
				Case "property"
					If fileScope Error( "Properties can only be declared inside a class, struct or interface" )
					decls.Push( ParseProperty( flags ) )
				Default
					Error( "Unexpected token '"+Toke+"'" )
				End
				
			Catch ex:ParseEx
				SkipToNextLine()
			End
			
			_meta=""
			
		Wend
		
		Return decls.ToArray()
	End
	
	Method ParseAliases( decls:Stack<Decl>,flags:Int )
	
		Local kind:=Parse()
		
		Try
			Repeat
			
				Local decl:=New AliasDecl
				
				decl.srcpos=SrcPos
				decl.kind=kind
				decl.docs=Docs()
				decl.meta=Meta()
				decl.flags=flags
				decl.ident=ParseIdent()
				decl.genArgs=ParseGenArgs()
				
				Parse( ":" )
				decl.type=ParseType()

				If flags & DECL_EXTERN
					If CParse( "=" ) decl.symbol=ParseString()
				Endif
				
				decl.endpos=EndPos
				decls.Push( decl )
			
			Until Not CParse( "," )
			
			ParseEol()
			
		Catch ex:ParseEx
		
			SkipToNextLine()
		End
	End
	
	Method ParseVars( decls:Stack<Decl>,flags:Int )
	
		Local kind:=Parse()
		
		Try
			Repeat
			
				Local decl:=New VarDecl
				
				decl.srcpos=SrcPos
				decl.kind=kind
				decl.docs=Docs()
				decl.meta=Meta()
				decl.flags=flags
				decl.ident=ParseIdent()
				
				If flags & DECL_EXTERN
					Parse( ":" )
					decl.type=ParseType()
					If CParse( "=" ) decl.symbol=ParseString()
				Else If CParse( ":" )
					decl.type=ParseType()
					If CParse( "=" ) decl.init=ParseExpr()
				Else If CParse( ":=" )
					decl.init=ParseExpr()
				Endif
				
				decl.endpos=EndPos
				decls.Push( decl )
				
			Until Not CParse( "," )
			
			ParseEol()
			
		Catch ex:ParseEx

			SkipToNextLine()
		End
	End
	
	Method ParseClass:ClassDecl( flags:Int )
	
		Local decl:=New ClassDecl
		decl.srcpos=SrcPos
		decl.kind=Parse()
		decl.docs=Docs()
		decl.meta=Meta()
		decl.ident="?????"
		
		flags&=(DECL_ACCESSMASK|DECL_EXTERN)
		
		Try
			decl.ident=ParseIdent()
			
			decl.genArgs=ParseGenArgs()
			
			If CParse( "extension" )
			
'				If decl.genArgs Error( "Extension classed cannot be generic" )
				
				decl.superType=New IdentExpr( decl.ident,decl.srcpos,decl.srcpos )

				If decl.genArgs
					Local exprs:=New Expr[decl.genArgs.Length]
					For Local i:=0 Until decl.genArgs.Length
						exprs[i]=New IdentExpr( decl.genArgs[i],decl.srcpos,decl.srcpos )
					Next
					decl.superType=New GenericExpr( decl.superType,exprs,decl.srcpos,decl.srcpos )
				Endif
				
				flags|=DECL_EXTENSION
			Endif
			
			If CParse( "extends" )
			
				If decl.kind="struct" Error( "Structs cannot use 'Extends'" )
			
				If flags & DECL_EXTENSION Error( "Extension classes cannot use 'Extends'" )
				
				If decl.kind="interface" Or decl.kind="protocol"
					decl.ifaceTypes=ParseTypes()
				Else
					decl.superType=ParseType()
				Endif
			Endif
			
			If CParse( "implements" )

				If flags & DECL_EXTENSION Error( "Extension classes cannot implement interfaces" )
				
				If decl.kind<>"class" And decl.kind<>"struct" Error( "'Implements' can only be used with classes and structs" )
				
				decl.ifaceTypes=ParseTypes()

			Endif
			
			Select Toke
			Case "virtual","abstract","final"

				If flags & DECL_EXTENSION Error( "Extension classes cannot have modifiers" )
				
				If decl.kind="interface" Error( "Interfaces are implicitly abstract" )
				
				If decl.kind="protocol" Error( "Protocols cannot have modifiers" )
				
				If CParse( "virtual" )
					flags|=DECL_VIRTUAL
				Else If CParse( "abstract" )
					flags|=DECL_ABSTRACT
				Else If CParse( "final" )
					flags|=DECL_FINAL
				Endif
				
			End
			
			If CParse( "=" )
				If Not (flags & DECL_EXTERN) Error( "Non-extern declaration cannot be assigned an extern symbol" )
				decl.symbol=ParseString()
			End
			
			If CParse( "where" )
				decl.whereExpr=ParseExpr()
			Endif
			
		
			ParseEol()
		
		Catch ex:ParseEx
		
			SkipToNextLine()
		End
		
		decl.flags=flags
		
		Local mflags:=(flags & (DECL_EXTERN|DECL_EXTENSION)) | DECL_PUBLIC

		If decl.kind="interface" Or decl.kind="protocol" mflags|=DECL_IFACEMEMBER|DECL_ABSTRACT
		
		decl.members=ParseDecls( mflags,False )
		
		Try
			Parse( "end" )
			CParse( decl.kind )
			ParseEol()
		Catch ex:ParseEx
			SkipToNextLine()
		End
		
		decl.endpos=EndPos
		Return decl
	End

	Method ParseFunc:FuncDecl( flags:Int )
	
		Local srcpos:=SrcPos
		Local kind:=Parse()
		Local docs:=Docs()
		Local meta:=Meta()
		Local ident:="?????"
		Local genArgs:String[]
		Local type:FuncTypeExpr
		Local whereExpr:Expr
		Local symbol:String
	
		Try

			Select kind
	
			Case "lambda"
			
			Case "getter"
			
				kind="method"
				flags|=DECL_GETTER
				
			Case "setter"
			
				kind="method"
				flags|=DECL_SETTER
			
			Case "operator"
			
				kind="method"
				flags|=DECL_OPERATOR
			
				Select Toke
				Case "to"
					ident=Parse()
				Case "*","/","+","-","&","|","~~"
					ident=Parse()
				Case "*=","/=","+=","-=","&=","|=","~~="
					ident=Parse()
				Case "<",">","<=",">=","=","<>","<=>"
					ident=Parse()
				Case "cast"
					ident=Parse()
				Case "["
					Bump()
					Parse( "]" )
					If CParse( "=" ) ident="[]=" Else ident="[]"
				Default
					Error( "Operator must be one of: * / + - & | ~~ [] < > <= >= = <> <=>" )
				End
				
			Case "method"
			
				If CParse( "new" )
					ident="new"
				Else If CParse( "to" )
					ident="to"
				Else
					ident=ParseIdent()
				Endif
				
			Case "function"
			
				flags&=~DECL_EXTENSION
			
				ident=ParseIdent()
				
			Default
			
				ident=ParseIdent()
				
				If ident="@typeof" ident="Typeof"
			End
			
			genArgs=ParseGenArgs()
			
			If genArgs And (flags & (DECL_SETTER|DECL_GETTER)) "Generic arguments can not appear here"
			
			If CParse( ":" )
				type=Cast<FuncTypeExpr>( ParseType() )
				If Not type Error( "Expecting function type" )
			Else
				type=ParseFuncType( New IdentExpr( "void",SrcPos,SrcPos ) )
			Endif
			
			If kind="lambda"
				For Local p:=Eachin type.params
					If p.init Error( "Lambda function parameters cannot have default values" )
				Next
			Endif
			
			If Not (flags & DECL_EXTERN)
				For Local param:=Eachin type.params
					If Not param.ident Error( "Missing parameter identifier" )
				Next
			Endif
			
			Select kind
			Case "property"
				If type.params.Length=0
					kind="method"
					flags|=DECL_GETTER
				Else If type.params.Length=1
					kind="method"
					flags|=DECL_SETTER
				Else
					Error( "Properties must have 0 or 1 parameters" )
				End
			Case "method"
				If (flags & DECL_GETTER)
					If type.params.Length<>0 Error( "Getters must have 0 parameters" )
				Else If (flags & DECL_SETTER )
					If type.params.Length<>1 Error( "Setters must have 1 parameter" )
				Endif
			End
			
			Select Toke
			Case "virtual","abstract","override","final","extension"
			
				If (flags & DECL_EXTENSION) Error( "Extension methods cannot have modifiers" )
			
				If (flags & DECL_IFACEMEMBER) Error( "Interface methods are implictly abstract" )
				
				If CParse( "virtual" )
					flags|=DECL_VIRTUAL
				Else If CParse( "abstract" )
					flags|=DECL_ABSTRACT
				Else If CParse( "override" )
					flags|=DECL_OVERRIDE
					If CParse( "final" ) flags|=DECL_FINAL
				Else If CParse( "final" )
					flags|=DECL_FINAL
				Else If CParse( "extension" )
					If kind<>"method" Or Not (flags & DECL_EXTERN) Error( "Only extern methods can be declared 'Extension'" )
					flags|=DECL_EXTENSION
				Endif
				
			End
			
			If CParse( "=" )
				
				If Not (flags & DECL_EXTERN) Error( "Non-extern declarations cannot be assigned an extern symbol" )
					
				symbol=ParseString()
			Endif

			If CParse( "where" )
				
				whereExpr=ParseExpr()
			Endif
			
			If CParse( "default" )
				
				If Not (flags & DECL_IFACEMEMBER) Error( "Only interface methods can be declared 'Default'" )
					
				flags&=~DECL_ABSTRACT
				flags|=DECL_DEFAULT
				
				If CParse( "virtual" ) flags|=DECL_VIRTUAL
			Endif
			
			ParseEol()
			
		Catch ex:ParseEx
		
			SkipToNextLine()
		End
		
		Local decl:=New FuncDecl
		decl.srcpos=srcpos
		decl.kind=kind
		decl.docs=docs
		decl.meta=meta
		decl.ident=ident
		decl.flags=flags
		decl.genArgs=genArgs
		decl.type=type
		decl.whereExpr=whereExpr
		decl.symbol=symbol
		
		If (flags & (DECL_EXTERN|DECL_ABSTRACT)) And Not (flags & DECL_DEFAULT)
			decl.endpos=EndPos
			Return decl
		Endif
		
		decl.stmts=ParseStmts( True )
		
		Try
		
			Select Toke
			Case "setter"
				If Not (flags & DECL_GETTER) Error( "Setter must appear after getter" )
			Case "getter"
				If Not (flags & DECL_SETTER) Error( "Getter must appear after setter" )
			Default
				Parse( "end" )
				If flags & (DECL_GETTER|DECL_SETTER)
					CParse( "property" )
				Else
					CParse( kind )
				Endif
				If kind<>"lambda" ParseEol()
			End
			
		Catch ex:ParseEx
		
			If kind="lambda" SkipToEol() Else SkipToNextLine()
		End
		
		decl.endpos=EndPos

		Return decl
	End
	
	Method ParseEnum:EnumDecl( flags:Int )
	
		Local decl:=New EnumDecl
		
		decl.srcpos=SrcPos
		decl.flags=flags
		decl.kind=Parse()
		decl.docs=Docs()
		decl.meta=Meta()
		
		Try
			decl.ident=ParseIdent()
			
			If CParse( "=" )
				If Not (flags & DECL_EXTERN) Error( "Non-extern declaration cannot be assigned an extern symbol" )
				decl.symbol=ParseString()
			Endif
			
			ParseEol()
			
		Catch ex:ParseEx
		
			SkipToNextLine()
		End
		
		Local members:=New Stack<Decl>
		
		While TokeType=TOKE_IDENT
		
			Try
				Local decl:=New VarDecl
				
				decl.srcpos=SrcPos
				decl.kind="const"
				decl.flags=DECL_PUBLIC|(flags & DECL_EXTERN)
				decl.ident=ParseIdent()
				decl.docs=Docs()
				decl.meta=Meta()
				
				If flags & DECL_EXTERN
					If CParse( "=" ) decl.symbol=ParseString()
				Else
					If CParse( "=" ) decl.init=ParseExpr()
				Endif
				
				decl.endpos=EndPos
				members.Push( decl )
				
				If Not CParse( "," ) ParseEol() Else CParseEol()
								
			Catch ex:ParseEx
			
				SkipToNextLine()
			End
		
		Wend

		decl.members=members.ToArray()
		
		Try
		
			Parse( "end" )
			CParse( "enum" )
			ParseEol()
			
		Catch ex:ParseEx
		
			SkipToNextLine()
		End
		
		decl.endpos=EndPos
		
		Return decl
	End
	
	Method ParseProperty:PropertyDecl( flags:Int )
	
		Local decl:=New PropertyDecl
		
		decl.srcpos=SrcPos
		decl.flags=flags
		decl.kind="property"
		decl.docs=Docs()
		decl.meta=Meta()
		
		Local func:=ParseFunc( flags )
		decl.ident=func.ident
		decl.genArgs=func.genArgs
		
		If func.IsGetter
		
			decl.getFunc=func
			
			If Toke="setter"
				decl.setFunc=ParseFunc( flags )
				decl.setFunc.ident=decl.ident
				decl.setFunc.genArgs=decl.genArgs
			Endif
			
		Else If func.IsSetter

			decl.setFunc=func

			If Toke="getter"
				decl.getFunc=ParseFunc( flags )
				decl.getFunc.ident=decl.ident
				decl.getFunc.genArgs=decl.genArgs
			Endif
			
		Endif
		
		decl.endpos=EndPos
		
		Return decl
	End
	
	Method ParseStmts:StmtExpr[]( block:Bool )
		If block Return ParseBlockStmts()
		Return ParseSimpleStmts()
	End
	
	Method ParseBlockStmts:StmtExpr[]()
	
		Local stmts:=New Stack<StmtExpr>
		
		While Toke
			
			Select Toke
			Case "if"
				stmts.Push( ParseIf() )
			Case "while"
				stmts.Push( ParseWhile() )
			Case "repeat"
				stmts.Push( ParseRepeat() )
			Case "for"
				stmts.Push( ParseFor() )
			Case "select"
				stmts.Push( ParseSelect() )
			Case "try"
				stmts.Push( ParseTry() )
			Case "local","const","global"
				Local decls:=New Stack<Decl>
				ParseVars( decls,DECL_PUBLIC )
				For Local decl:=Eachin decls
					stmts.Push( New VarDeclStmtExpr( Cast<VarDecl>(decl),decl.srcpos,decl.endpos ) )
				Next
			Case "end","endif","wend","next","until","forever","else","elseif","setter","getter","case","default","catch"
				Exit
			Default
				Try
					Repeat
						stmts.Push( ParseSimpleStmt() )
					Until Not CParse( ";" )
					ParseEol()
				Catch ex:ParseEx
					SkipToNextLine()
				End
			End
		Wend
		
		Return stmts.ToArray()
	End
	
	Method ParseSimpleStmts:StmtExpr[]()
	
		Local stmts:=New Stack<StmtExpr>
		
		Try
			Repeat
				stmts.Push( ParseSimpleStmt() )
			Until Not CParse( ";" )
		Catch ex:ParseEx
			SkipToEol()
		End
		
		Return stmts.ToArray()
	End
	
	Method ParseIf:IfStmtExpr()
	
		Local srcpos:=SrcPos
		Local cond:Expr
		Local block:Bool
		
		Try
			Parse( "if" )
			
			cond=ParseExpr()
			
			CParse( "then" )
			
			block=CParseEol()
			
'			If Not block CParse( "then" )
			
		Catch ex:ParseEx
		
			SkipToNextLine()
			
			If Not block Return New IfStmtExpr( cond,Null,Null,srcpos,EndPos )

		End
		
		Local stmts:=ParseStmts( block )
		Local expr:=New IfStmtExpr( cond,stmts,Null,srcpos,EndPos )
		Local pred:=expr
		
		While Toke="elseif" Or Toke="else"
		
			Local srcpos:=SrcPos
			Local toke:=Parse()
			Local cond:Expr

			If toke="else" And CParse( "if" ) toke="elseif"

			Try
				If toke="elseif"
				
					cond=ParseExpr()
					CParse( "then" )

				Endif

				If block ParseEol()
			
			Catch ex:ParseEx
			
				SkipToNextLine()
				If Not block Return expr
			
			End
			
			Local stmts:=ParseStmts( block )
			
			Local expr:=New IfStmtExpr( cond,stmts,Null,srcpos,EndPos )
			pred.succ=expr
			pred=expr
			
			If toke="else" Exit
		Wend
		
		Try
			If block
				If CParse( "end" ) CParse( "if" ) Else Parse( "endif" )
			Endif
			
			ParseEol()
			
		Catch ex:ParseEx

			SkipToNextLine()
		End
		
		pred.endpos=EndPos
		
		Return expr
	End
	
	Method ParseWhile:WhileStmtExpr()
	
		Local srcpos:=SrcPos
		Local cond:Expr
		
		Try
			Parse( "while" )
			cond=ParseExpr()
			ParseEol()
		Catch ex:ParseEx
			SkipToNextLine()
		End
		
		Local stmts:=ParseStmts( True )
		
		Try
			If CParse( "end" ) Then CParse( "while" ) Else Parse( "wend" )
			ParseEol()
		Catch ex:ParseEx
			SkipToNextLine()
		End
		
		Return New WhileStmtExpr( cond,stmts,srcpos,EndPos )
	End
	
	Method ParseRepeat:RepeatStmtExpr()
	
		Local srcpos:=SrcPos
		Local cond:Expr
		Local block:=False
		
		Try
			Parse( "repeat" )
			ParseEol()
		Catch ex:ParseEx
			SkipToNextLine()
		End
		
		Local stmts:=ParseStmts( True )
		
		Try
			If CParse( "until" ) 
				cond=ParseExpr()
			Else If Not CParse( "forever" )
				Error( "Expecting 'until' or 'forever'" )
			Endif
			ParseEol()
		Catch ex:ParseEx
			SkipToNextLine()
		End
		
		Return New RepeatStmtExpr( stmts,cond,srcpos,EndPos )
	End
	
	Method ParseFor:ForStmtExpr()
	
		Local varIdent:String
		Local varType:Expr
		Local varExpr:Expr
		Local kind:String
		Local init:Expr
		Local cond:Expr
		Local incr:Expr
		
		Local srcpos:=SrcPos
		
		Local vsrcpos:=srcpos
		
		Try
			Parse( "for" )
			
			If CParse( "local" )
				
				vsrcpos=SrcPos
			
				varIdent=ParseIdent()
				
				If CParse( ":" )
				
					varType=ParseType()
					
					Parse( "=" )
				Else
				
					Parse( ":=" )
				Endif
			Else
			
				varExpr=ParsePostfixExpr()
				
				Parse( "=" )
			Endif
			
			If CParse( "eachin" )
			
				init=ParseExpr()
				kind="eachin"
			
			Else
			
				init=ParseExpr()
				
				If Toke<>"to" And Toke<>"until" Error( "Expecting 'To' or 'Until'" )
				
				kind=Toke
				Bump()
				
				cond=ParseExpr()
				
				If CParse( "step" ) incr=ParseExpr()
			
			Endif
			
			ParseEol()
			
		Catch ex:ParseEx
		
			SkipToNextLine()
			
		End
		
		Local vendpos:=SrcPos
		
		Local stmts:=ParseStmts( True )
		
		Try
			If CParse( "end" ) CParse( "for" ) Else Parse( "next" )
			ParseEol()
		Catch ex:ParseEx
			SkipToNextLine()
		End
		
		Return New ForStmtExpr( varIdent,varType,varExpr,kind,init,cond,incr,stmts,srcpos,EndPos,vsrcpos,vendpos )
	
	End
	
	Method ParseSelect:SelectStmtExpr()
	
		Local srcpos:=SrcPos
		Local expr:Expr
		
		Try
			Parse( "select" )
			
			expr=ParseExpr()
			
			ParseEol()
			
		Catch ex:ParseEx
		
			SkipToNextLine()
		End
		
		Local cases:=New Stack<CaseStmtExpr>
		
		While Toke="case"
			
			Local srcpos:=SrcPos
			
			Bump()

			Local exprs:=New Stack<Expr>

			Try
			
				Repeat
					exprs.Push( ParseExpr() )
				Until Not CParse( "," )
				
				CParseEol()

			Catch ex:ParseEx
			
				SkipToNextLine()
			End
			
			Local stmts:=ParseStmts( True )
			
			cases.Push( New CaseStmtExpr( exprs.ToArray(),stmts,srcpos,SrcPos ) )
		Wend
		
		If cases.Empty ErrorNx( "Select statement must have at least one case" )
			
		If Toke="default"
			
			Local srcpos:=SrcPos
			
			Bump()
		
			CParseEol()
		
			Local stmts:=ParseStmts( True )
			
			cases.Push( New CaseStmtExpr( Null,stmts,srcpos,SrcPos ) )
		Endif
		
		Try
			Parse( "end" )
			CParse( "select" )
			ParseEol()
		Catch ex:ParseEx
			SkipToNextLine()
		End
		
		Return New SelectStmtExpr( expr,cases.ToArray(),srcpos,EndPos )
	
	End
	
	Method ParseTry:TryStmtExpr()
	
		Local srcpos:=SrcPos
	
		Try
		
			Parse( "try" ) 
			ParseEol()
			
		Catch ex:ParseEx
		
			SkipToNextLine()
		End
		
		Local stmts:=ParseStmts( True )
		
		Local catches:=New Stack<CatchStmtExpr>
		
		While Toke="catch"
		
			Local srcpos:=SrcPos
			
			Bump()
			
			Local varIdent:String
			Local varType:Expr
			
			Try
				varIdent=ParseIdent()
				Parse( ":" )
				varType=ParseType()
				
				ParseEol()
				
			Catch ex:ParseEx
			
				SkipToNextLine()
			End
			
			Local stmts:=ParseStmts( True )
			
			catches.Push( New CatchStmtExpr( varIdent,varType,stmts,srcpos,SrcPos ) )
		Wend
		
		Try
		
			Parse( "end" )
			CParse( "try" )
			ParseEol()
			
		Catch ex:ParseEx
		
			SkipToNextLine()
		End
		
		Return New TryStmtExpr( stmts,catches.ToArray(),srcpos,EndPos )
	End
	
	'At end of statement?
	Method AtEos:Bool()
		Return TokeType=TOKE_EOL Or Toke=";" Or Toke="else" Or Toke="elseif"
	End
	
	'THROWS!
	Method ParseSimpleStmt:StmtExpr()
	
		Local srcpos:=SrcPos

		Select Toke
		Case "print"
			Bump()
			Local expr:=ParseExpr()
			Return New PrintStmtExpr( expr,srcpos,EndPos )
		Case "return"
			Bump()
			Local expr:Expr
			If Not AtEos() expr=ParseExpr()
'			If TokeType And TokeType<>TOKE_EOL And Toke<>";" And Toke<>"else" And Toke<>"elseif"
'				expr=ParseExpr()
'			Endif
			Return New ReturnStmtExpr( expr,srcpos,EndPos )
		Case "throw"
			Bump()
			Local expr:Expr
			If Not AtEos() expr=ParseExpr()
'			Local expr:=ParseExpr()
			Return New ThrowStmtExpr( expr,srcpos,EndPos )
		Case "continue"
			Bump()
			Return New ContinueStmtExpr( srcpos,EndPos )
		Case "exit"
			Bump()
			Return New ExitStmtExpr( srcpos,EndPos )
		End

		Return ParseExprStmt()
	End
	
	'THROWS!
	Method ParseExprStmt:StmtExpr()
		
		Local srcpos:=SrcPos
		Local expr:=ParsePostfixExpr()
		
		Select Toke
		Case "=","*=","/=","+=","-=","&=","|=","~~="
			Local op:=Parse()
			Local rhs:=ParseExpr()
			Return New AssignStmtExpr( op,expr,rhs,srcpos,EndPos )
		Case "shl","shr","mod"	'Note: Can't overload && || in C++? News to me...
			Local op:=Parse()
			Parse( "=" )
			Local rhs:=ParseExpr()
			Return New AssignStmtExpr( op+"=",expr,rhs,srcpos,EndPos )
		End
		
		'Ok, ugly, but look for Blah.New() here...
		'
		Local iexpr:=Cast<InvokeExpr>( expr )
		If iexpr
			Local mexpr:=Cast<MemberExpr>( iexpr.expr )
			If mexpr And mexpr.ident="new" Return New InvokeNewStmtExpr( mexpr.expr,iexpr.args,srcpos,EndPos )
		Endif
		
		Return New EvalStmtExpr( expr,srcpos,EndPos )
	End
	
	'THROWS!
	Method ParseGenArgs:String[]()
	
		If Not CParse( "<" ) Return Null
		
		Local args:=New StringStack
		Repeat
			args.Push( ParseIdent() )
		Until Not CParse( "," )
	
		Parse( ">" )
		
		Return args.ToArray()
	End
	
	Method IsTypeIdent:Bool( ident:String )
		Select ident
		Case "void","bool","byte","ubyte","short","ushort","int","uint","long","ulong","float","double","string","object","throwable","variant","cstring","wstring","typeinfo"
			Return True
		End
		Return False
	End
	
	'THROWS!
	Method ParseTypes:Expr[]()
		Local types:=New Stack<Expr>
		Repeat
			types.Push( ParseType() )
		Until Not CParse( "," )
		Return types.ToArray()
	End
	
	'THROWS!
	Method ParseFuncType:FuncTypeExpr( retType:Expr )
	
		Parse( "(" )
		
		Local params:=New Stack<VarDecl>
		
		If Not CParse( ")" )
		
			Repeat

				Local decl:=New VarDecl
				decl.srcpos=SrcPos
				decl.kind="param"
				decl.flags=DECL_PUBLIC
				
				Local ident:=CParseIdent()
				
				If ident
					If CParse( ":" )
						decl.ident=ident
						decl.type=ParseType()
						If CParse( "=" ) decl.init=ParseExpr()
					Else
						decl.type=ParseType( New IdentExpr( ident,decl.srcpos,EndPos ) )
					Endif
				Else
					decl.type=ParseType()
				Endif
				
				decl.endpos=EndPos
				
				params.Push( decl )
				
			Until Not CParse( "," )
			
			Parse( ")" )
			
		Endif
		
		Return New FuncTypeExpr( retType,params.ToArray(),retType.srcpos,EndPos )
	End
	
	'THROWS!
	Method ParseIdentType:IdentExpr()
	
		Local srcpos:=SrcPos
		
		Local ident:=CParseIdent()
		If Not ident And IsTypeIdent( Toke ) ident=Parse()
		If Not ident Error( "Expecting type identifier" )
		Return New IdentExpr( ident,srcpos,EndPos )
	End

	'THROWS!	
	Method ParseBaseType:Expr( identType:IdentExpr=Null )
	
		Local type:Expr=identType
		
		If Not type type=ParseIdentType()
		Local srcpos:=type.srcpos
		
		Repeat
			If Toke="."
				Bump()
				Local ident:=ParseIdent()
				type=New MemberExpr( type,ident,srcpos,EndPos )
			Else If Toke="<"
				Bump()
				Local args:=New Stack<Expr>
				Repeat
					args.Push( ParseType() )
				Until Not CParse( "," )
				Parse( ">" )
				type=New GenericExpr( type,args.ToArray(),srcpos,EndPos )
			Else
				Exit
			Endif
		Forever
		
		While CParse( "ptr" )
			type=New PointerTypeExpr( type,srcpos,EndPos )
		Wend
		
		Return type
	End
	
	'THROWS!
	Method ParseType:Expr( identType:IdentExpr=Null )
	
		Local type:=ParseBaseType( identType )
		Local srcpos:=type.srcpos
		
		Repeat
			Select Toke
			Case "["
			
				'Arrays are backwards! Yikes!
				Local head:ArrayTypeExpr
				Local tail:=head
			
				While CParse( "[" )
					Local rank:=1
					While CParse( "," )
						rank+=1
					Wend
					Parse( "]" )
					
					Local type:=New ArrayTypeExpr( Null,rank,srcpos,EndPos )
					If tail tail.type=type Else head=type
					tail=type
				Wend
				
				tail.type=type
				type=head
				
			Case "("
				type=ParseFuncType( type )
			Default
				Exit
			End
		Forever
		
		Return type
	End
	
	'THROWS! Some ugly stunt parsing to handle operator New.
	Method ParseNewType:Expr()
	
		Local srcpos:=SrcPos
		Local type:=ParseBaseType()
		
		Repeat
			Select Toke
			Case "["
			
				'Array types are backwards!
				'	
				Local head:ArrayTypeExpr
				Local tail:=head
				Local done:=False
					
				While Toke="["

					BeginTryParse()
					Parse()
					
					Local rank:=1
					While CParse( "," )
						rank+=1
					Wend
					
					If Not CParse( "]" )
						TryParseFailed()
						done=True
						Exit
					Endif
					
					EndTryParse()
					
					Local type:=New ArrayTypeExpr( Null,rank,srcpos,EndPos )
					If tail tail.type=type Else head=type
					tail=type
					
				Wend
				
				If Not head Exit

				tail.type=type
				type=head
				
				If done Exit
				
			Case "("
			
				BeginTryParse()
				
				Try
					Local ftype:=ParseFuncType( type )
					
					If Toke<>"[" And Toke<>"("
						TryParseFailed()
						Exit
					Endif
					
					EndTryParse()
					type=ftype
					
				Catch ex:TryParseEx
				
					TryParseFailed()
					Exit
					
				End
			Default
				Exit
			End
		Forever
		
		Return type
	End

	'THROWS!
	Method ParsePrimaryExpr:Expr()
		
		CParseEol()
		
		Local srcpos:=SrcPos
	
		Select Toke
		Case "("
			Bump()
			Local expr:=ParseExpr()
			Parse( ")" )
			Return expr
		Case "self"
			Bump()
			Return New SelfExpr( srcpos,EndPos )
		Case "super"
			Bump()
			Return New SuperExpr( srcpos,EndPos )
		Case "null"
			Bump()
			Return New NullExpr( srcpos,EndPos )
		Case "new"
		
			Bump()
			Local type:=ParseNewType()
			
			If CParse( "[" )
				Local sizes:=ParseExprs()
				Parse( "]" )
				
				Local head:=New ArrayTypeExpr( Null,sizes.Length,srcpos,EndPos )
				Local tail:=head
				
				While CParse( "[" )
					Local rank:=1
					While CParse( "," )
						rank+=1
					Wend
					Parse( "]" )
					
					Local type:=New ArrayTypeExpr( Null,rank,srcpos,EndPos )
					tail.type=type
					tail=type
				Wend
				
				tail.type=type
				
				Local inits:Expr[]
				If CParse( "(" ) 
					inits=ParseExprs()
					Parse( ")" )
				Endif
				
				Return New NewArrayExpr( head,sizes,inits,srcpos,EndPos )
			Endif
			
			If Toke="("
				Local atype:=Cast<ArrayTypeExpr>( type )
				If atype
					Bump()
					Local inits:=ParseExprs()
					Parse( ")" )
					Return New NewArrayExpr( atype,Null,inits,srcpos,EndPos )
				Endif
				Local args:=ParseInvokeArgs()
				Return New NewObjectExpr( type,args,srcpos,EndPos )
			End
			
			Return New NewObjectExpr( type,Null,srcpos,EndPos )
			
		Case "lambda"
		
			Local decl:=ParseFunc( DECL_PUBLIC )
			Return New LambdaExpr( decl,srcpos,EndPos )
			
		Case "cast"
		
			Bump()
			Parse( "<" )
			Local type:=ParseType()
			Parse( ">" )
			Parse( "(" )
			Local expr:=ParseExpr()
			Parse( ")" )
			Return New CastExpr( type,expr,srcpos,EndPos )
			
		Case "typeof"
		
			Bump()
			If CParse( "<" )
				Local expr:=ParseType()
				Parse( ">" )
				Return New TypeofExpr( expr,True,srcpos,EndPos )
			Else If CParse( "(" )
				Local expr:=ParseExpr()
				Parse( ")" )
				Return New TypeofExpr( expr,False,srcpos,EndPos )
			Endif
			
			Error( "Expecting 'Typeof' argument" )
			
		Case "true","false"
		
			Local value:=Parse()
			
			Return New LiteralExpr( value,TOKE_KEYWORD,Null,srcpos,EndPos )
		End
		
		Select TokeType
		Case TOKE_KEYWORD
		
			If IsTypeIdent( Toke )
			
				Local ident:=Parse()
				
				If Toke="ptr" Or Toke="("
					Local type:=ParseBaseType( New IdentExpr( ident,srcpos,EndPos ) )
					
					Parse( "(" )
					Local expr:=ParseExpr()
					Parse( ")" )
					Return New CastExpr( type,expr,srcpos,EndPos )
				Endif
				
				Return New IdentExpr( ident,srcpos,EndPos )
				
			Endif
			
		Case TOKE_IDENT
		
			Return New IdentExpr( ParseIdent(),srcpos,EndPos )
			
		Case TOKE_INTLIT,TOKE_FLOATLIT
		
			Local toke:=Toke
			Local tokeType:=TokeType
			Local typeExpr:Expr

			Bump()
			If CParse( ":" ) typeExpr=ParseType()
			
			Return New LiteralExpr( toke,tokeType,typeExpr,srcpos,EndPos )
			
		Case TOKE_STRINGLIT

			Local toke:=Toke
			Local tokeType:=TokeType
			Local typeExpr:Expr

			Bump()
		
			Return New LiteralExpr( toke,tokeType,typeExpr,srcpos,EndPos )
			
		End
		
		Error( "Expecting expression but encountered '"+Toke+"'" )
		Return Null
	End
	
	'THROWS!
	Method ParsePostfixExpr:Expr()
	
		Local expr:=ParsePrimaryExpr()
		
		While Toke
			Local srcpos:=SrcPos
			
			Select Toke
			Case "?."
				Bump()
				Local ident:=ParseIdent()
				If Toke="("
					Local args:=ParseInvokeArgs()
					expr=New SafeInvokeExpr( expr,ident,args,srcpos,EndPos )
				Else
					expr=New SafeMemberExpr( expr,ident,srcpos,EndPos )
				Endif
			Case "."
				Bump()
				Local ident:String
				If CParse( "new" )
					ident="new"
				Else If CParse( "typeof" )
					ident="Typeof"
				Else
					ident=ParseIdent()
				Endif
				expr=New MemberExpr( expr,ident,srcpos,EndPos )
			Case "->"
				Bump()
				Local ident:=ParseIdent()
				Local zero:=New LiteralExpr( "0",TOKE_INTLIT,Null,srcpos,EndPos )
				expr=New IndexExpr( expr,New Expr[]( zero ),srcpos,EndPos )
				expr=New MemberExpr( expr,ident,srcpos,EndPos )
			Case "["
				Bump()
				Local args:=ParseExprs()
				Parse( "]" )
				expr=New IndexExpr( expr,args,srcpos,EndPos )
			Case "("
				Local args:=ParseInvokeArgs()
				expr=New InvokeExpr( expr,args,srcpos,EndPos )
			Case "<"
				BeginTryParse()
				Local args:=New Stack<Expr>
				Try
					Bump()
					Repeat
						args.Push( ParseType() )
					Until Not CParse( "," )
					Parse( ">" )
				Catch ex:TryParseEx
					TryParseFailed()
					Exit
				End
				EndTryParse()
				expr=New GenericExpr( expr,args.ToArray(),srcpos,EndPos )
			Default
				Exit
			End
		Wend
		
		Return expr
	End
	
	'THROWS!
	Method ParsePrefixExpr:Expr()
		Local srcpos:=SrcPos
		Select Toke
		Case "varptr"
			Bump()
			Return New VarptrExpr( ParsePrefixExpr(),srcpos,EndPos )
		Case "+","-","~~","not"
			Local op:=Parse()
			Return New UnaryopExpr( op,ParsePrefixExpr(),srcpos,EndPos )
		End
		Return ParsePostfixExpr()
	End

	'THROWS!
	Method ParseMuldivExpr:Expr()
		Local srcpos:=SrcPos
		Local expr:=ParsePrefixExpr()
		Repeat
			Select Toke
			Case "*","/","mod"
				Local op:=Parse()
				expr=New BinaryopExpr( op,expr,ParsePrefixExpr(),srcpos,EndPos )
			Default
				Exit
			End
		Forever
		Return expr
	End
	
	'THROWS!
	Method ParseAddsubExpr:Expr()
		Local srcpos:=SrcPos
		Local expr:=ParseMuldivExpr()
		Repeat
			Select Toke
			Case "+","-"
				Local op:=Parse()
				expr=New BinaryopExpr( op,expr,ParseMuldivExpr(),srcpos,EndPos )
			Default
				Exit
			End
		Forever
		Return expr
	End
	
	'THROWS!
	Method ParseShiftExpr:Expr()
		Local srcpos:=SrcPos
		Local expr:=ParseAddsubExpr()
		Repeat
			Select Toke
			Case "shl","shr"
				Local op:=Parse()
				expr=New BinaryopExpr( op,expr,ParseAddsubExpr(),srcpos,EndPos )
			Default
				Exit
			End
		Forever
		Return expr
	
	End
	
	'THROWS!
	Method ParseBitandExpr:Expr()
		Local srcpos:=SrcPos
		Local expr:Expr=ParseShiftExpr()
		Repeat
			Select Toke
			Case "&","~~"
				Local op:=Parse()
				expr=New BinaryopExpr( op,expr,ParseShiftExpr(),srcpos,EndPos )
			Default
				Exit
			End Select
		Forever
		Return expr
	End
	
	'THROWS!
	Method ParseBitorExpr:Expr()
		Local srcpos:=SrcPos
		Local expr:Expr=ParseBitandExpr()
		Repeat
			Select Toke
			Case "|"
				Local op:=Parse()
				expr=New BinaryopExpr( op,expr,ParseBitandExpr(),srcpos,EndPos )
			Default
				Exit
			End
		Forever
		Return expr
	End
	
	'THROWS!
	Method ParseOrderExpr:Expr()
		Local srcpos:=SrcPos
		Local expr:=ParseBitorExpr()
		Repeat
			Select Toke
			Case "<=>"
				Local op:=Parse()
				expr=New BinaryopExpr( op,expr,ParseBitorExpr(),srcpos,EndPos )
			Default
				Exit
			End
		Forever
		Return expr
	End
		
	'THROWS!
	Method ParseCompareExpr:Expr()
		Local srcpos:=SrcPos
		Local expr:=ParseOrderExpr()
		Repeat
			Select Toke
			Case "<",">","<=",">="
				Local op:=Parse()
				expr=New BinaryopExpr( op,expr,ParseOrderExpr(),srcpos,EndPos )
			Default
				Exit
			End
		Forever
		Return expr
	End
	
	'THROWS!
	Method ParseExtendsExpr:Expr()
		Local srcpos:=SrcPos
		Local expr:=ParseCompareExpr()
		Repeat
			Select Toke
			Case "extends","implements"
				Local op:=Parse()
				expr=New ExtendsExpr( op,expr,ParseType(),srcpos,EndPos )
			Default
				Exit
			End
		Forever
		Return expr
	End
	
	'THROWS!
	Method ParseEqualsExpr:Expr()
		Local srcpos:=SrcPos
		Local expr:=ParseExtendsExpr()
		Repeat
			Select Toke
			Case "=","<>"
				Local op:=Parse()
				expr=New BinaryopExpr( op,expr,ParseExtendsExpr(),srcpos,EndPos )
			Default
				Exit
			End
		Forever
		Return expr
	End
	
	'THROWS!
	Method ParseAndExpr:Expr()
		Local srcpos:=SrcPos
		Local expr:Expr=ParseEqualsExpr()
		Repeat
			Select Toke
			Case "and"
				Local op:=Parse()
				expr=New BinaryopExpr( op,expr,ParseEqualsExpr(),srcpos,EndPos )
			Default
				Exit
			End
		Forever
		Return expr
	End
	
	'THROWS!
	Method ParseOrExpr:Expr()
		Local srcpos:=SrcPos
		Local expr:Expr=ParseAndExpr()
		Repeat
			Select Toke
			Case "or"
				Local op:=Parse()
				expr=New BinaryopExpr( op,expr,ParseAndExpr(),srcpos,EndPos )
			Default
				Exit
			End
		Forever
		Return expr
	End
	
	Method ParseIfThenElseExpr:Expr()
	
		Local srcpos:=SrcPos

		Local expr:Expr=ParseOrExpr()
		If Not CParse( "?" ) Return expr
		
		If CParse( "else" )
			Return New ElvisExpr( expr,ParseOrExpr(),srcpos,EndPos )
		Endif
		
		Local thenExpr:=ParseIfThenElseExpr()

		Parse( "else" )

		Local elseExpr:=ParseOrExpr()

		Return New IfThenElseExpr( expr,thenExpr,elseExpr,srcpos,EndPos )
	End
		
	'THROWS!
	Method ParseExpr:Expr()
		Return ParseIfThenElseExpr()
	End
	
	'THROWS!
	Method ParseExprs:Expr[]()
	
		Local exprs:=New Stack<Expr>
		
		Repeat
			exprs.Push( ParseExpr() )
		Until Not CParse( "," )
		
		Return exprs.ToArray()
	End

	'THROWS!	
	Method ParseInvokeArgs:Expr[]()
	
		Local exprs:=New Stack<Expr>
		
		Parse( "(" )
		
		If Not CParse( ")" )
			Repeat
				If Toke=")"
					exprs.Push( Null )
					Exit
				Else If Toke=","
					exprs.Push( Null )
				Else
					exprs.Push( ParseExpr() )
				Endif
			Until Not CParse( "," )
			
			Parse( ")" )
		Endif
		
		Return exprs.ToArray()
	End
	
	Method EatEols()
		While TokeType=TOKE_EOL
			Bump()
		Wend
	End
	
	Method SkipToEol()
		While TokeType And TokeType<>TOKE_EOL
			Bump()
		Wend
	End
	
	Method SkipToNextLine()
		SkipToEol()
		EatEols()
	End
	
	'THROWS!
	Method ParseEol()
		If TokeType And TokeType<>TOKE_EOL Error( "Expecting end of line" )
		EatEols()
	End
	
	Method CParseEol:Bool()
		If TokeType<>TOKE_EOL Return False
		EatEols()
		Return True
	End
	
	'THROWS!
	Method ParseIdent:String()
		If CParse( "@" ) And TokeType Return "@"+Parse()
		If TokeType<>TOKE_IDENT Error( "Expecting identifier" )
		Local ident:=Toke
		Bump()
		Return ident
	End
	
	Method CParseIdent:String()
		If TokeType<>TOKE_IDENT Return ""
		Local ident:=Toke
		Bump()
		Return ident
	End
	
	'THROWS!
	Method ParseString:String()
		If TokeType<>TOKE_STRINGLIT Error( "Expecting string literal" )
		Local str:=Toke.Slice( 1,-1 )
		Bump()
		Return str
	End
	
	'THROWS!	
	Method Parse( toke:String )
		If Toke<>toke Error( "Expecting '"+toke+"' but encountered '"+Toke+"'" )
		Bump()
	End

	Method CParse:Bool( toke:String )
		If Toke<>toke Return False
		Bump()
		Return True
	End

	Method BeginTryParse()
		_stateStack.Push( _toker.State )
	End
	
	Method TryParseFailed()
		Local state:=_stateStack.Pop()
		_toker.State=state
	End
	
	Method EndTryParse()
		_stateStack.Pop()
	End
	
	Method Parse:String()
		Local toke:=Toke
		Bump()
		Return toke
	End

	Method Docs:String()
		If Not _docs.Length Return ""
		Local docs:=_docs.Join( "~n" )
		_docs.Clear()
		Return docs
	End
	
	Method Bump:String()
	
		If Not _fdecl Return _toker.Bump()
	
		Local ptoke:=Toke

		Repeat
		
			If Not _toker.Bump() Exit
			
			If _toker.TokeType=TOKE_PREPROC
			
				PreProcess( _toker.Toke )
				
				Continue
				
			Else If _cc.Top<>1
			
				Local pos:=_toker.LinePos
			
				While _toker.TokeType And _toker.TokeType<>TOKE_EOL
					_toker.Bump()
				Wend
				
				If _doccing
					Local text:=_toker.Text.Slice( pos,_toker.TokePos )
					_docs.Push( text )
				Endif

				Continue
				
			Else
			
				If _toker.TokeType=TOKE_EOL And (ptoke="(" Or ptoke="[" Or ptoke="," ) Continue
				
			Endif
			
			Exit
			
		Forever
		
		Return _toker.Toke
	End
	
	Property Toke:String()
		Return _toker.Toke
	End
	
	Property TokeType:Int()
		Return _toker.TokeType
	End
	
	Property SrcPos:Int()
		Return _toker.SrcPos
	End
	
	Property EndPos:Int()
		Return _toker.EndPos
	End
	
	'Throw a ParseEx
	'
	Method Error( msg:String )
	
		If Not _stateStack.Empty Throw New TryParseEx
	
		Throw New ParseEx( msg,_fdecl ? _fdecl.path Else "",SrcPos )
	End
	
	'Generate a ParseEx without throwing an exception
	'
	Method ErrorNx( msg:String )

		If Not _stateStack.Empty Throw New TryParseEx

		New ParseEx( msg,_fdecl.path,SrcPos )
	End
	
	Field _fdecl:FileDecl
	Field _toker:Toker
	Field _meta:String
	Field _stateStack:=New Stack<Toker>
	Field _usings:=New StringStack
	Field _errors:=New Stack<ParseEx>
	
	'***** Messy Preprocessor - FIXME! *****
	
	Field _ppsyms:StringMap<String>
	
	Field _cc:=New Stack<Int>
'	Field _ccnest:Int
'	Field _ifnest:Int
	Field _docs:=New StringStack
	Field _doccing:Bool
	Field _imports:=New StringStack
	Field _reflects:=New StringStack
	
	Method IsBool:Bool( v:String )
		Return v="true" Or v="false"
	End
	
	Method ToBool:String( v:String )
		If v="false" Or v="~q~q" Return "false"
		Return "true"
	End

	Method EvalPrimary:String()
	
		If CParse( "(" )
			Local expr:=Eval()
			Parse( ")" )
			Return expr
		Endif
		
		Select TokeType
		Case TOKE_IDENT
			Local id:=Parse()
			Local t:=_ppsyms[id]
			If Not t Error( "symbol '"+id+"' not found" )
			Return t
		Case TOKE_STRINGLIT
			Return Parse()
		End

		Error( "unexpected token '"+Toke+"'" )
		
		Return Null
	End
	
	Method EvalUnary:String()
		If CParse( "not" )
			Local expr:=ToBool( EvalUnary() )
			If expr="true" Return "false" Else Return "true"
		Endif
		Return EvalPrimary()
	End
	
	Method EvalEquals:String()
		Local lhs:=EvalUnary()
		While Toke="=" Or Toke="<>"
			Local op:=Parse()
			Local rhs:=EvalUnary()
			If IsBool( lhs ) Or IsBool( rhs ) 
				lhs=ToBool( lhs )
				rhs=ToBool( rhs )
			Endif
			
			If (lhs="~q"+HostOS+"~q" And rhs="~qdesktop~q") Or (lhs="~qdesktop~q" And rhs="~q"+HostOS+"~q" ) 
				Error( "__TARGET__=~qdesktop~q no longer supported! Use boolean __DESKTOP_TARGET__ instead!" )
			Endif
			
			Select op
			Case "=" If lhs=rhs lhs="true" Else lhs="false"
			Case "<>" If lhs<>rhs lhs="true" Else lhs="false"
			End
		Wend
		Return  lhs
	End
	
	Method EvalAnd:String()
		Local lhs:=EvalEquals()
		While CParse( "and" )
			lhs=ToBool( lhs )
			Local rhs:=ToBool( EvalEquals() )
			If lhs="true" And rhs="true" lhs="true" Else lhs="false"
		Wend
		Return lhs
	End
	
	Method EvalOr:String()
		Local lhs:=EvalAnd()
		While CParse( "or" )
			lhs=ToBool( lhs )
			Local rhs:=ToBool( EvalAnd() )
			If lhs="true" Or rhs="true" lhs="true" Else lhs="false"
		Wend
		Return lhs
	End
	
	Method Eval:String()
		Return EvalOr()
	End
	
	Method EvalBool:Bool()
		Return ToBool( Eval() )="true"
	End
	
	Method PreProcess( text:String )
	
		Local p:=New Parser( text.Slice( 1 ),_ppsyms )
	
		Try
		
			Select p.Toke.ToLower()
			Case "if"
			
				If _cc.Top=1
					p.Bump()
					If p.EvalBool() _cc.Push( 1 ) Else _cc.Push( 0 )
				Else
					_cc.Push( -1 )
				Endif
				
			Case "else","elseif"
			
				If _cc.Top=1
				
					_cc.Pop()
					_cc.Push( -1 )
					
				Else If _cc.Top=0

					Local t:=True

					If p.CParse( "else" )
						If p.CParse( "if" ) t=p.EvalBool()
					Else 
						p.Bump()
						t=p.EvalBool()
					Endif
					
					If t
						_cc.Pop()
						_cc.Push( 1 )
					Endif
				
				Endif
				
			Case "end","endif"
			
				If _cc.Length=1 p.Error( "#end without matching #if or #rem" )
			
				If p.CParse( "end" )
					p.CParse( "if" )
				Else
					p.Bump()
				End
				
				_cc.Pop()
				
				If _cc.Top=1 _doccing=False
				
			Case "rem"
			
				If _cc.Top=1 And p.Bump()="monkeydoc" And Builder.opts.makedocs

					Local qhelp:=p._toker.Text.Slice( p._toker.TokePos+9 ).Trim()
					_docs.Clear()
					_docs.Push( qhelp )
					_doccing=True

				Endif
				
				_cc.Push( -1 )
				
			Case "import"
			
				If _cc.Top=1

					p.Bump()
					
					Local path:=p.ParseString()
					
					p.ParseEol()
					
					If path.StartsWith( "<" ) And path.EndsWith( ">" )
					
						If Not ExtractExt( path ) path=path.Slice( 0,-1 )+".monkey2>"
						
					Else If Not path.Contains( "@/" ) And Not path.EndsWith( "/" )
					
						If Not ExtractExt( path ) path+=".monkey2"
						
					Endif
						
					path+="["+SrcPos+"]"
						
					_imports.Push( path )
				Endif
				
			Case "reflect"
				
				If _cc.Top=1
					
					p.Bump()
					
					Local path:=p.ParseIdent()
					
					While p.CParse( "." )
						If p.CParse( "." )
							path+=".."
							Exit
						Endif
						path+="."+p.ParseIdent()
					Wend
					
					p.ParseEol()
					
					_reflects.Push( path )
				Endif
				
			Case "print"
			
				If _cc.Top=1
					p.Bump()				
					Print p.Eval()
				Endif
				
			Default
				
				If _cc.Top=1
					p.Error( "Unrecognized preprocessor directive '"+p.Toke+"'" )
				Endif
			End
			
		Catch ex:ParseEx
			
			ErrorNx( ex.msg )
		End
		
	End
	
End
