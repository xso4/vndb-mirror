-- Column selection dropdown for tables. Assumes that the currently selected
-- columns are in the query string as the 'c' parameter, e.g.:
--
--   ?c=column_id&c=modified&...
--
-- Accepts a [ $current_url, [ list of columns ] ] from Perl, e.g.:
--
--   [ '?c=column_id', [
--     [ 'column_id', 'Column Label' ],
--     [ 'modified',  'Date modified' ],
--     ...
--   ] ]
--
-- TODO: Convert all uses of this module to the more flexible TableOpts.
module ColSelect exposing (main)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Browser
import Browser.Navigation exposing (load)
import Set
import Erl -- elm/url can't extract a full list of query parameters and hence can't be used to modify a parameter without removing all others.
import Lib.DropDown as DD
import Lib.Api as Api
import Lib.Html exposing (..)


main : Program (String, Columns) Model Msg
main = Browser.element
  { init   = \e -> (init e, Cmd.none)
  , view   = view
  , update = update
  , subscriptions = \model -> DD.sub model.dd
  }


type alias Columns = List (String, String)

type alias Model =
  { cols : Columns
  , url  : Erl.Url -- Without the "c" parameter
  , sel  : Set.Set String
  , dd   : DD.Config Msg
  }


init : (String, Columns) -> Model
init (u, c) =
  { cols = c
  , url  = Erl.removeQuery "c" <| Erl.parse u
  , sel  = Set.fromList <| Erl.getQueryValuesForKey "c" <| Erl.parse u
  , dd   = DD.init "colselect" Open
  }


type Msg
  = Open Bool
  | Toggle String Bool
  | Update


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Open b     -> ({ model | dd = DD.toggle model.dd b }, Cmd.none)
    Toggle s b -> ({ model | sel = if b then Set.insert s model.sel else Set.remove s model.sel }, Cmd.none)
    Update -> (model, load <| Erl.toString <| List.foldl (\s u -> Erl.addQuery "c" s u) model.url <| Set.toList model.sel)


view : Model -> Html Msg
view model =
  let item (cid, cname) = li [ ] [ linkRadio (Set.member cid model.sel) (Toggle cid) [ text cname ] ]
  in
    DD.view model.dd Api.Normal
      (text "Select columns")
      (\_ -> [ ul []
        <| List.map item model.cols
        ++ [ li [ ] [ input [ type_ "button", class "submit", value "update", onClick Update ] [] ] ]
      ])
