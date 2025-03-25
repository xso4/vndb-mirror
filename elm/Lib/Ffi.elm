-- Elm 0.19: "We've removed all Native modules and plugged all XSS vectors,
--            it's now impossible to talk with Javascript other than with ports!"
-- Me: "Oh yeah? I'll just run sed over the generated Javascript!"

-- This module is a hack to work around the lack of an FFI (Foreign Function
-- Interface) in Elm. The functions in this module are stubs, their
-- implementations are replaced by the Makefile with calls to
-- window.elmFfi_<name> and the actual implementations are in elm-support.js.
--
-- Use sparingly, all of this will likely break in future Elm versions.
module Lib.Ffi exposing (..)

import Html
import Html.Attributes
import Browser.Dom
import Task

-- Set the innerHTML attribute of a node
innerHtml : String -> Html.Attribute msg
innerHtml s = Html.Attributes.title ""

-- Like Browser.Dom.focus, except it can call any function (without arguments)
elemCall : String -> String -> Task.Task Browser.Dom.Error ()
elemCall s = Browser.Dom.focus

-- Format a floating point number with a fixed number of fractional digits.
-- (The coinop-logan/elm-format-number package seems to be the go-to way to do
-- this in Elm, but why reimplement float operations when the browser can do it
-- just as well?)
fmtFloat : Float -> Int -> String
fmtFloat _ _ = ""
