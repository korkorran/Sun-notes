(* The paste shortcut in a text field.

   The window carries no menu bar, and on macOS that is exactly where the
   standard editing key equivalents live: with no Edit menu holding a Paste
   item, the system never turns Cmd+V into a paste, and the only way in is the
   web engine's own context menu. The keystroke does reach the page as an
   ordinary keydown though, so the shortcut can be served here instead — the
   page reads the clipboard itself and splices the text in.

   This is a shim for a platform behaviour that is missing, not application
   logic, which is why it sits apart from the widgets that use it. *)

open Vdom

(* Reading the clipboard is asynchronous, so it is a command, like every other
   answer the page cannot produce on the spot. *)
type 'msg Vdom.Cmd.t += Paste of int * int

(** Read the clipboard and paste it over [start]..[stop] of the focused field. *)
let paste ~start ~stop = Paste (start, stop)

(* Paste into the focused text field, and let the field's own input event carry
   the text into the model.

   Splicing the string in OCaml and letting the model redraw the field would be
   the obvious thing, and it is what this module used to do. It costs the
   caret: the textarea is drawn from the model, so the redraw assigns [value],
   and assigning [value] sends the caret to the end of the document. Going
   through the DOM instead leaves the field and the model holding the same
   string, which is the one case vdom knows to leave alone
   (vdom_blit.ml: [| "value", String s when s = Element.value dom -> ()]).

   [setRangeText] with ["end"] places the caret just after what it inserted.
   It is set again on the next turn of the event loop, after the redraw has had
   its chance — belt and braces, since the field's value is not ours alone. *)
let paste_focused ~start ~stop =
  let el = Jv.get (Jv.get Jv.global "document") "activeElement" in
  (* No selection to speak of: the focus is not in a text field, and there is
     nowhere to paste. *)
  if Jv.is_none (Jv.get el "selectionStart") then ()
  else
    let clipboard = Jv.get (Jv.get Jv.global "navigator") "clipboard" in
    ignore
      (Jv.Promise.then'
         (Jv.call clipboard "readText" [||])
         (fun text ->
           ignore
             (Jv.call el "setRangeText"
                [| text; Jv.of_int start; Jv.of_int stop; Jv.of_string "end" |]);
           let caret = start + String.length (Jv.to_string text) in
           let place () =
             Jv.set el "selectionStart" (Jv.of_int caret);
             Jv.set el "selectionEnd" (Jv.of_int caret)
           in
           place ();
           ignore
             (Jv.call el "dispatchEvent"
                [|
                  Jv.new' (Jv.get Jv.global "Event")
                    [| Jv.of_string "input"; Jv.obj [| ("bubbles", Jv.true') |] |];
                |]);
           ignore
             (Jv.call Jv.global "setTimeout" [| Jv.repr place; Jv.of_int 0 |]);
           Jv.null)
         (* Nothing readable means nothing to paste. Someone who pressed a
            shortcut has no use for an error about it. *)
         (fun _ -> Jv.null))

(** The command handler to merge into the one given to [Vdom_blit.run ~env]. *)
let env =
  Vdom_blit.cmd
    {
      Vdom_blit.Cmd.f =
        (fun ctx cmd ->
          ignore ctx;
          match cmd with
          | Paste (start, stop) ->
              paste_focused ~start ~stop;
              true
          | _ -> false);
    }

(** Fire [f start stop] when the paste shortcut is pressed in a text field,
    where [start] and [stop] delimit the selection the pasted text replaces —
    the same pair a real paste event would carry.

    The default is prevented for that combination only, so every other
    keystroke reaches the field untouched. *)
let on_shortcut f =
  on_with_options "keydown"
    Decoder.(
      let+ key = field "key" string
      and+ code = field "code" string
      and+ meta = field "metaKey" bool
      and+ ctrl = field "ctrlKey" bool
      and+ start = field "target.selectionStart" int
      and+ stop = field "target.selectionEnd" int in
      (* [code] names the physical key, so the shortcut still lands on a layout
         that does not put V where QWERTY does; [key] covers the case of a
         remapped keyboard where it does not. *)
      if (meta || ctrl) && (key = "v" || key = "V" || code = "KeyV") then
        {
          msg = Some (f start stop);
          stop_propagation = false;
          prevent_default = true;
        }
      else { msg = None; stop_propagation = false; prevent_default = false })
