(* A string as a JSON literal, ready for [Webview.return]'s result or for
   interpolation into an [eval] snippet. *)
let quote s = Yojson.Safe.to_string (`String s)

(* Decode a binding request: [req] is the JSON array of the JS arguments, and
   this returns every string it holds, in order. Arguments that are not strings
   are skipped rather than reported: a binding states what it expects by
   matching on the list it gets back. A malformed request gives [None].

   Yojson does the parsing. Writing it by hand meant getting JSON's escapes
   right -- \uXXXX, and the surrogate pairs that carry a character above the
   BMP -- none of which OCaml's own [Scanf] "%S" understands, since it reads
   OCaml literals rather than JSON ones. *)
let json_string_args req =
  match Yojson.Safe.from_string req with
  | `List args ->
      Some (List.filter_map (function `String s -> Some s | _ -> None) args)
  | _ | (exception Yojson.Json_error _) -> None

(* The first string argument of a request, for the bindings that take exactly
   one. A request holding no string at all (["[]"], ["[42]"]) has none. *)
let json_string_arg req =
  match json_string_args req with Some (s :: _) -> Some s | _ -> None
