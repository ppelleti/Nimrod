#
#
#           The Nimrod Compiler
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Template evaluation engine. Now hygienic.

import
  strutils, options, ast, astalgo, msgs, os, idents, wordrecg, renderer, 
  rodread

type
  TemplCtx {.pure, final.} = object
    owner, genSymOwner: PSym
    mapping: TIdTable # every gensym'ed symbol needs to be mapped to some
                      # new symbol

proc evalTemplateAux(templ, actual: PNode, c: var TemplCtx): PNode =
  #inc genSymBaseId
  case templ.kind
  of nkSym:
    var s = templ.sym
    if s.owner.id == c.owner.id:
      if s.kind == skParam:
        result = copyTree(actual.sons[s.position])
      else:
        InternalAssert sfGenSym in s.flags
        var x = PSym(IdTableGet(c.mapping, s))
        if x == nil:
          x = copySym(s, false)
          x.owner = c.genSymOwner
          IdTablePut(c.mapping, s, x)
        result = newSymNode(x, templ.info)
    else:
      result = copyNode(templ)
  of nkNone..nkIdent, nkType..nkNilLit: # atom
    result = copyNode(templ)
  else:
    result = copyNode(templ)
    newSons(result, sonsLen(templ))
    for i in countup(0, sonsLen(templ) - 1): 
      result.sons[i] = evalTemplateAux(templ.sons[i], actual, c)

proc evalTemplateArgs(n: PNode, s: PSym): PNode =
  # if the template has zero arguments, it can be called without ``()``
  # `n` is then a nkSym or something similar
  var a: int
  case n.kind
  of nkCall, nkInfix, nkPrefix, nkPostfix, nkCommand, nkCallStrLit:
    a = sonsLen(n)
  else: a = 0
  var f = s.typ.sonsLen
  if a > f: GlobalError(n.info, errWrongNumberOfArguments)

  result = copyNode(n)
  for i in countup(1, f - 1):
    var arg = if i < a: n.sons[i] else: copyTree(s.typ.n.sons[i].sym.ast)
    if arg == nil or arg.kind == nkEmpty:
      LocalError(n.info, errWrongNumberOfArguments)
    addSon(result, arg)

var evalTemplateCounter* = 0
  # to prevent endless recursion in templates instantiation

proc evalTemplate*(n: PNode, tmpl, genSymOwner: PSym): PNode =
  inc(evalTemplateCounter)
  if evalTemplateCounter > 100:
    GlobalError(n.info, errTemplateInstantiationTooNested)
    result = n

  # replace each param by the corresponding node:
  var args = evalTemplateArgs(n, tmpl)
  var ctx: TemplCtx
  ctx.owner = tmpl
  ctx.genSymOwner = genSymOwner
  initIdTable(ctx.mapping)
  result = evalTemplateAux(tmpl.getBody, args, ctx)
  
  dec(evalTemplateCounter)