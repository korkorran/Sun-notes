(* Elm-style application: the UI is a pure function of a model, and every
   interaction goes through a message. Nothing here looks up or mutates a DOM
   node by hand — [Vdom_blit] diffs the tree returned by [view] and patches the
   document itself.

   This file is only the assembly. The two panes are components of their own —
   [FileExplorer] on the left, [ContentEditor] on the right — each with its own
   model, messages and update. All that is left here is holding one of each,
   forwarding messages to the right one, and carrying across the single thing
   they have to say to each other: the explorer opened a file, the editor shows
   it. *)

type msg =
  | Explorer_msg of FileExplorer.msg
  | Editor_msg of ContentEditor.msg

type model = {
  explorer : FileExplorer.model;
  editor : ContentEditor.model;
}

let init =
  let explorer, cmd = FileExplorer.init in
  ( { explorer; editor = ContentEditor.init },
    Vdom.Cmd.map (fun m -> Explorer_msg m) cmd )

(** Act on what the explorer reported. This is the whole of the coupling
    between the two panes. *)
let apply_out model = function
  | FileExplorer.File_opened (path, contents) ->
      { model with editor = ContentEditor.open_file model.editor ~path ~contents }
  | FileExplorer.File_created path ->
      { model with editor = ContentEditor.open_new_file model.editor ~path }

(* Each pane runs its own update; whatever it produces comes back wrapped, so
   the message types never mix. *)
let update model = function
  | Explorer_msg m ->
      let explorer, cmd, out = FileExplorer.update model.explorer m in
      ( List.fold_left apply_out { model with explorer } out,
        Vdom.Cmd.map (fun m -> Explorer_msg m) cmd )
  | Editor_msg m ->
      let editor, cmd = ContentEditor.update model.editor m in
      ({ model with editor }, Vdom.Cmd.map (fun m -> Editor_msg m) cmd)

let view { explorer; editor } =
  let open Vdom in
  div
    ~a:[ class_ "layout" ]
    [
      div
        ~a:[ class_ "controls" ]
        [ map (fun m -> Explorer_msg m) (FileExplorer.view explorer) ];
      (* The id is kept so the rules of style.css still apply. *)
      div
        ~a:[ attr "id" "out" ]
        ((* A read in flight is announced above the editor rather than in place
            of it: replacing the pane would take the tab strip away with it. *)
         (if FileExplorer.is_reading explorer then
            [ elt "p" ~a:[ class_ "status" ] [ text "reading\xe2\x80\xa6" ] ]
          else [])
        @ [ map (fun m -> Editor_msg m) (ContentEditor.view editor) ]);
    ]

let app = Vdom.app ~init ~update ~view ()

(* What the native menu bar asks the page to do; see run/main.ml for the bar
   itself.

   The two file actions are messages, borrowed from the panes that own them —
   a menu item cannot build a private message, so each pane exposes the one it
   is willing to share.

   The three edit actions are not messages at all. They go to the browser's
   own editing commands, which act on whichever text field has the focus, and
   the edit they make fires that field's input event — so the model is brought
   up to date by the path that already exists for typing. Doing it through the
   model instead would mean reading the selection out of the DOM and handing it
   back, for no gain.

   Paste is the exception a browser forces: execCommand("paste") is refused to
   page script, so the clipboard is read here and the text inserted as if it
   had been typed. insertText fires the same input event. *)
let exec_command cmd arg =
  ignore
    (Jv.call
       (Jv.get Jv.global "document")
       "execCommand"
       [| Jv.of_string cmd; Jv.of_bool false; arg |])

let on_menu instance action =
  match action with
  | "open-folder" ->
      Vdom_blit.process instance (Explorer_msg FileExplorer.pick_folder_msg)
  | "save" ->
      Vdom_blit.process instance (Editor_msg ContentEditor.save_active_msg)
  | "cut" -> exec_command "cut" Jv.null
  | "copy" -> exec_command "copy" Jv.null
  | "paste" ->
      (* The same implementation the Cmd+V shortcut uses — see clipboard.ml.
         Only the range has to be found here, the shortcut getting it from the
         keydown event instead. *)
      let el = Jv.get (Jv.get Jv.global "document") "activeElement" in
      let sel = Jv.get el "selectionStart" in
      if Jv.is_none sel then ()
      else
        Clipboard.paste_focused ~start:(Jv.to_int sel)
          ~stop:(Jv.to_int (Jv.get el "selectionEnd"))
  (* An unknown action means this page and that menu disagree about their
     vocabulary. Nothing useful to do about it here. *)
  | _ -> ()

let run () =
  (* This code is executed once the view is initialized, the elements are all
  ready *)
  let container =
    Option.get (Js_browser.Document.get_element_by_id Js_browser.document "app")
  in
  let env = Vdom_blit.merge [ Binding.env; Clipboard.env ] in
  let instance = Vdom_blit.run ~env ~container app in
  (* The one function the native side calls into the page. Registered after the
     application is running, so that a menu item chosen early has somewhere to
     send its message. *)
  Binding.register "sunNotesMenu" (fun action ->
      on_menu instance (Jv.to_string action))

let () =
  Js_browser.Window.add_event_listener Js_browser.window
    Js_browser.Event.DOMContentLoaded
    (fun _ -> run ())
    false
