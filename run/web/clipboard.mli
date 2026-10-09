(** Serving the paste shortcut from the page.

    The window has no menu bar, so macOS never turns Cmd+V into a paste: the
    keystroke arrives as a plain keydown and nothing acts on it. These two
    pieces put the behaviour back — an attribute that catches the shortcut, and
    a command that reads the clipboard — for any text field that wants it. *)

val on_shortcut : (int -> int -> 'msg) -> 'msg Vdom.attribute
(** [on_shortcut f] fires [f start stop] when the shortcut is pressed in a text
    field, [start] and [stop] delimiting the selection the pasted text is meant
    to replace. Other keystrokes are left alone. *)

val paste : start:int -> stop:int -> 'msg Vdom.Cmd.t
(** The command to answer [on_shortcut] with. It reads the clipboard and pastes
    it over [start]..[stop] of the focused field, leaving the caret after the
    inserted text. Nothing happens if there is nothing to read. *)

val paste_focused : start:int -> stop:int -> unit
(** [paste] as a plain effect, for a caller with no command context — the
    native menu bar's Paste item. *)

val env : Vdom_blit.env
(** To be merged into the environment given to [Vdom_blit.run]. *)
