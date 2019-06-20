import macros, tables
import common

proc procDefs(node: NimNode): seq[NimNode] =
  # Gets all the proc definitions from the statement list
  for child in node:
    if child.kind == nnkProcDef:
      result.add(child)

proc getParams(formalParams: NimNode): seq[Table[string, NimNode]] =
  # Find all the parameters and build a table with needed information
  assert(formalParams[0].len > 1, "RPC procs need to return a future")
  assert(formalParams[0][0].strVal == "Future", "RPC procs need to return a future")
  for param in formalParams:
    if param.kind == nnkIdentDefs:
      let defaultIdx = param.len - 1
      let typeIdx = param.len - 2
      for i in 0 ..< typeIdx:
        result.add(
          {
            "name": param[i],
            "nameStr": newStrLitNode(param[i].strVal),
          }.toTable
        )


proc procBody(p: NimNode, uri = "/rpc"): NimNode =
  let nameStr = newStrLitNode(p.name.strVal)
  let formalParams = p.findChild(it.kind == nnkFormalParams)
  let retType = formalParams[0][1]
  let params = formalParams.getParams()
  let req = genSym()

  var paramJson = nnkStmtList.newTree()
  for param in params:
    let nameStr = param["nameStr"]
    let name = param["name"]
    paramJson.add(
      quote do:
        `req`["body"]["params"][`nameStr`] = `name`.toJs()
    )
  
  result = quote do:
    let `req` = newJsObject()
    `req`["method"] = cstring"POST"
    `req`["body"] = newJsObject()
    `req`["body"]["jsonrpc"] = cstring("2.0")
    `req`["body"]["id"] = 0
    `req`["body"]["method"] = cstring`nameStr`
    `req`["body"]["params"] = newJsObject()
    `paramJson`
    `req`["body"] = JSON.stringify(`req`["body"])
    result = fetch(cstring(`uri`), `req`)
      .then(respToJson)
      .then(handleRpcResponse[`retType`])

proc rpcClient*(name: NimNode, uri: string, body: NimNode): NimNode =
  result = newStmtList()
  let procs = procDefs(body)
  for p in procs:
    let newBody = procBody(p, uri)
    p[p.len - 1] = newBody
    result.add(p)
  result.add(rpcServiceType(name, procs))
  result.add(rpcServiceObject(name, procs, uri))
  if defined(nerveRpcDebug):
    echo repr result