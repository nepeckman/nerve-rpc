import macros, tables
import common

proc networkProcBody(p: NimNode): NimNode =
  let nameStr = newStrLitNode(p.name.strVal)
  let formalParams = p.findChild(it.kind == nnkFormalParams)
  let retType = formalParams[0][1]
  let params = formalParams.getParams()
  let req = genSym()
  let driver = ident("nerveDriver")
  let newJsObject = if defined(js): ident("newJsObject") else: ident("newJObject")
  let toJs = if defined(js): ident("toJs") else: ident("%")

  var paramJson = nnkStmtList.newTree()
  for param in params:
    let nameStr = param["nameStr"]
    let name = param["name"]
    paramJson.add(
      quote do:
        `req`["params"][`nameStr`] = `toJs` `name`
    )
  
  result = quote do:
    let `req` = `newJsObject`()
    `req`["jsonrpc"] = `toJs` "2.0"
    `req`["id"] = `toJs` 0
    `req`["method"] = `toJs` `nameStr`
    `req`["params"] = `newJsObject`()
    `paramJson`
    result = `driver`(`req`)
      .then(handleRpcResponse[`retType`])

proc networkProcs*(procs: seq[NimNode]): NimNode =
  result = newStmtList()
  for p in procs:
    let networkProc = copy(p)
    networkProc[0] = networkProcName(p[0].basename.strVal())
    networkProc[networkProc.len - 1] = networkProcBody(networkProc)
    networkProc.findChild(it.kind == nnkFormalParams).add(
      nnkIdentDefs.newTree(
        ident("nerveDriver"),
        ident("NerveDriver"),
        newEmptyNode()
      )
    )
    result.add(networkProc)

