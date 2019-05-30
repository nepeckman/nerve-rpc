import macros, jsffi, tables
import fetch, common

proc procDefs(node: NimNode): seq[NimNode] =
  # Gets all the proc definitions from the statement list
  for child in node:
    if child.kind == nnkProcDef:
      result.add(child)

proc getParams(formalParams: NimNode): seq[Table[string, NimNode]] =
  # Find all the parameters and build a table with needed information
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


proc procBody(p: NimNode): NimNode =
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
    `req`["body"]["method"] = cstring`nameStr`
    `req`["body"]["params"] = newJsObject()
    `paramJson`
    `req`["body"] = JSON.stringify(`req`["body"])
    result = fetch(cstring("/rpc"), `req`)
      .then(proc (resp: JsObject): JsObject = respJson(resp))
      .then(proc (data: JsObject): `retType` = data.to(`retType`))

proc rpcClient*(name, body: NimNode): NimNode =
  result = newStmtList()
  let procs = procDefs(body)
  for p in procs:
    let newBody = procBody(p)
    p[p.len - 1] = newBody
    result.add(p)
  result.add(rpcServiceType(name, procs))
  result.add(rpcServiceObject(name, procs))
  if defined(nerveRpcDebug):
    echo repr result