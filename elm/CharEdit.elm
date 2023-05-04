module CharEdit exposing (main)

import Html exposing (..)
import Html.Events exposing (..)
import Html.Keyed as K
import Html.Attributes exposing (..)
import Browser
import Browser.Navigation exposing (load)
import Dict
import Set
import Task
import Process
import File exposing (File)
import File.Select as FSel
import Lib.Ffi as Ffi
import Lib.Util exposing (..)
import Lib.Html exposing (..)
import Lib.TextPreview as TP
import Lib.Autocomplete as A
import Lib.Api as Api
import Lib.Editsum as Editsum
import Lib.RDate as RDate
import Lib.Image as Img
import Gen.Release as GR
import Gen.CharEdit as GCE
import Gen.Types as GT
import Gen.Api as GApi


main : Program GCE.Recv Model Msg
main = Browser.element
  { init   = \e -> (init e, Cmd.none)
  , view   = view
  , update = update
  , subscriptions = always Sub.none
  }


type Tab
  = General
  | Image
  | Traits
  | VNs
  | All

type SelOpt = Spoil Int | Lie

type alias Model =
  { state       : Api.State
  , tab         : Tab
  , invalidDis  : Bool
  , editsum     : Editsum.Model
  , name        : String
  , latin       : Maybe String
  , alias       : String
  , description : TP.Model
  , gender      : String
  , spoilGender : Maybe String
  , bMonth      : Int
  , bDay        : Int
  , age         : Maybe Int
  , sBust       : Int
  , sWaist      : Int
  , sHip        : Int
  , height      : Int
  , weight      : Maybe Int
  , bloodt      : String
  , cupSize     : String
  , main        : Maybe String
  , mainRef     : Bool
  , mainHas     : Bool
  , mainName    : String
  , mainSearch  : A.Model GApi.ApiCharResult
  , mainSpoil   : Int
  , image       : Img.Image
  , traits      : List GCE.RecvTraits
  , traitSearch : A.Model GApi.ApiTraitResult
  , traitSel    : (String, SelOpt)
  , vns         : List GCE.RecvVns
  , vnSearch    : A.Model GApi.ApiVNResult
  , releases    : Dict.Dict String (List GCE.RecvReleasesRels) -- vid -> list of releases
  , id          : Maybe String
  }


init : GCE.Recv -> Model
init d =
  { state       = Api.Normal
  , tab         = General
  , invalidDis  = False
  , editsum     = { authmod = d.authmod, editsum = TP.bbcode d.editsum, locked = d.locked, hidden = d.hidden, hasawait = False }
  , name        = d.name
  , latin       = d.latin
  , alias       = d.alias
  , description = TP.bbcode d.description
  , gender      = d.gender
  , spoilGender = d.spoil_gender
  , bMonth      = d.b_month
  , bDay        = if d.b_day == 0 then 1 else d.b_day
  , age         = d.age
  , sBust       = d.s_bust
  , sWaist      = d.s_waist
  , sHip        = d.s_hip
  , height      = d.height
  , weight      = d.weight
  , bloodt      = d.bloodt
  , cupSize     = d.cup_size
  , main        = d.main
  , mainRef     = d.main_ref
  , mainHas     = d.main /= Nothing
  , mainName    = d.main_name
  , mainSearch  = A.init ""
  , mainSpoil   = d.main_spoil
  , image       = Img.info d.image_info
  , traits      = d.traits
  , traitSearch = A.init ""
  , traitSel    = ("", Spoil 0)
  , vns         = d.vns
  , vnSearch    = A.init ""
  , releases    = Dict.fromList <| List.map (\v -> (v.id, v.rels)) d.releases
  , id          = d.id
  }


encode : Model -> GCE.Send
encode model =
  { id          = model.id
  , editsum     = model.editsum.editsum.data
  , hidden      = model.editsum.hidden
  , locked      = model.editsum.locked
  , name        = model.name
  , latin       = model.latin
  , alias       = model.alias
  , description = model.description.data
  , gender      = model.gender
  , spoil_gender= model.spoilGender
  , b_month     = model.bMonth
  , b_day       = model.bDay
  , age         = model.age
  , s_bust      = model.sBust
  , s_waist     = model.sWaist
  , s_hip       = model.sHip
  , height      = model.height
  , weight      = model.weight
  , bloodt      = model.bloodt
  , cup_size    = model.cupSize
  , main        = if model.mainHas then model.main else Nothing
  , main_spoil  = model.mainSpoil
  , image       = model.image.id
  , traits      = List.map (\t -> { tid = t.tid, spoil = t.spoil, lie = t.lie }) model.traits
  , vns         = List.map (\v -> { vid = v.vid, rid = v.rid, spoil = v.spoil, role = v.role }) model.vns
  }

mainConfig : A.Config Msg GApi.ApiCharResult
mainConfig = { wrap = MainSearch, id = "mainadd", source = A.charSource }

traitConfig : A.Config Msg GApi.ApiTraitResult
traitConfig = { wrap = TraitSearch, id = "traitadd", source = A.traitSource }

vnConfig : A.Config Msg GApi.ApiVNResult
vnConfig = { wrap = VnSearch, id = "vnadd", source = A.vnSource }

type Msg
  = Editsum Editsum.Msg
  | Tab Tab
  | Invalid Tab
  | InvalidEnable
  | Submit
  | Submitted GApi.Response
  | Name String
  | Latin String
  | Alias String
  | Desc TP.Msg
  | Gender String
  | SpoilGender (Maybe String)
  | BMonth Int
  | BDay Int
  | Age (Maybe Int)
  | SBust (Maybe Int)
  | SWaist (Maybe Int)
  | SHip (Maybe Int)
  | Height (Maybe Int)
  | Weight (Maybe Int)
  | BloodT String
  | CupSize String
  | MainHas Bool
  | MainSearch (A.Msg GApi.ApiCharResult)
  | MainSpoil Int
  | ImageSet String Bool
  | ImageSelect
  | ImageSelected File
  | ImageMsg Img.Msg
  | TraitDel Int
  | TraitSel String SelOpt
  | TraitSpoil Int Int
  | TraitLie Int Bool
  | TraitSearch (A.Msg GApi.ApiTraitResult)
  | VnRel Int (Maybe String)
  | VnRole Int String
  | VnSpoil Int Int
  | VnDel Int
  | VnRelAdd String String
  | VnSearch (A.Msg GApi.ApiVNResult)
  | VnRelGet String GApi.Response


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Editsum m  -> let (nm,nc) = Editsum.update m model.editsum in ({ model | editsum = nm }, Cmd.map Editsum nc)
    Tab t      -> ({ model | tab = t }, Cmd.none)
    Invalid t  -> if model.invalidDis || model.tab == All || model.tab == t then (model, Cmd.none) else
                  ({ model | tab = t, invalidDis = True }, Task.attempt (always InvalidEnable) (Ffi.elemCall "reportValidity" "mainform" |> Task.andThen (\_ -> Process.sleep 100)))
    InvalidEnable -> ({ model | invalidDis = False }, Cmd.none)
    Name s     -> ({ model | name = s }, Cmd.none)
    Latin s -> ({ model | latin = if s == "" then Nothing else Just s }, Cmd.none)
    Alias s    -> ({ model | alias = s }, Cmd.none)
    Desc m     -> let (nm,nc) = TP.update m model.description in ({ model | description = nm }, Cmd.map Desc nc)
    Gender s   -> ({ model | gender = s }, Cmd.none)
    SpoilGender s->({model | spoilGender = s }, Cmd.none)
    BMonth n   -> ({ model | bMonth = n }, Cmd.none)
    BDay n     -> ({ model | bDay   = n }, Cmd.none)
    Age s      -> ({ model | age    = s }, Cmd.none)
    SBust s    -> ({ model | sBust  = Maybe.withDefault 0 s }, Cmd.none)
    SWaist s   -> ({ model | sWaist = Maybe.withDefault 0 s }, Cmd.none)
    SHip s     -> ({ model | sHip   = Maybe.withDefault 0 s }, Cmd.none)
    Height s   -> ({ model | height = Maybe.withDefault 0 s }, Cmd.none)
    Weight s   -> ({ model | weight = s }, Cmd.none)
    BloodT s   -> ({ model | bloodt = s }, Cmd.none)
    CupSize s  -> ({ model | cupSize= s }, Cmd.none)

    MainHas b  -> ({ model | mainHas = b }, Cmd.none)
    MainSearch m ->
      let (nm, c, res) = A.update mainConfig m model.mainSearch
      in case res of
        Nothing -> ({ model | mainSearch = nm }, c)
        Just m1 ->
          case m1.main of
            Just m2 -> ({ model | mainSearch = A.clear nm "", main = Just m2.id, mainName = m2.title }, c)
            Nothing -> ({ model | mainSearch = A.clear nm "", main = Just m1.id, mainName = m1.title }, c)
    MainSpoil n -> ({ model | mainSpoil = n }, Cmd.none)

    ImageSet s b -> let (nm, nc) = Img.new b s in ({ model | image = nm }, Cmd.map ImageMsg nc)
    ImageSelect -> (model, FSel.file ["image/png", "image/jpeg", "image/webp"] ImageSelected)
    ImageSelected f -> let (nm, nc) = Img.upload Api.Ch f in ({ model | image = nm }, Cmd.map ImageMsg nc)
    ImageMsg m -> let (nm, nc) = Img.update m model.image in ({ model | image = nm }, Cmd.map ImageMsg nc)

    TraitDel idx       -> ({ model | traits = delidx idx model.traits }, Cmd.none)
    TraitSel id opt    -> ({ model | traitSel = (id, opt) }, Cmd.none)
    TraitSpoil idx spl -> ({ model | traits = modidx idx (\t -> { t | spoil = spl }) model.traits }, Cmd.none)
    TraitLie idx v     -> ({ model | traits = modidx idx (\t -> { t | lie = v }) model.traits }, Cmd.none)
    TraitSearch m ->
      let (nm, c, res) = A.update traitConfig m model.traitSearch
      in case res of
        Nothing -> ({ model | traitSearch = nm }, c)
        Just t ->
          let n = { tid = t.id, spoil = t.defaultspoil, lie = False, new = True
                  , name = t.name, group = t.group_name
                  , hidden = t.hidden, locked = t.locked, applicable = t.applicable }
          in
            if not t.applicable || t.hidden || List.any (\l -> l.tid == t.id) model.traits
            then ({ model | traitSearch = A.clear nm "" }, c)
            else ({ model | traitSearch = A.clear nm "", traits = model.traits ++ [n] }, c)

    VnRel   idx r -> ({ model | vns = modidx idx (\v -> { v | rid   = r }) model.vns }, Cmd.none)
    VnRole  idx s -> ({ model | vns = modidx idx (\v -> { v | role  = s }) model.vns }, Cmd.none)
    VnSpoil idx n -> ({ model | vns = modidx idx (\v -> { v | spoil = n }) model.vns }, Cmd.none)
    VnDel   idx   -> ({ model | vns = delidx idx model.vns }, Cmd.none)
    VnRelAdd vid title ->
      let rid = Dict.get vid model.releases |> Maybe.andThen (\rels -> List.filter (\r -> not (List.any (\v -> v.vid == vid && v.rid == Just r.id) model.vns)) rels |> List.head |> Maybe.map (\r -> r.id))
      in ({ model | vns = model.vns ++ [{ vid = vid, title = title, rid = rid, spoil = 0, role = "primary" }] }, Cmd.none)
    VnSearch m ->
      let (nm, c, res) = A.update vnConfig m model.vnSearch
      in case res of
        Nothing -> ({ model | vnSearch = nm }, c)
        Just vn ->
          if List.any (\v -> v.vid == vn.id) model.vns
          then ({ model | vnSearch = A.clear nm "" }, c)
          else ({ model | vnSearch = A.clear nm "", vns = model.vns ++ [{ vid = vn.id, title = vn.title, rid = Nothing, spoil = 0, role = "primary" }] }
               , Cmd.batch [c, if Dict.member vn.id model.releases then Cmd.none else GR.send { vid = vn.id } (VnRelGet vn.id)])
    VnRelGet vid (GApi.Releases r) -> ({ model | releases = Dict.insert vid r model.releases }, Cmd.none)
    VnRelGet _ r -> ({ model | state = Api.Error r }, Cmd.none) -- XXX

    Submit -> ({ model | state = Api.Loading }, GCE.send (encode model) Submitted)
    Submitted (GApi.Redirect s) -> (model, load s)
    Submitted r -> ({ model | state = Api.Error r }, Cmd.none)


isValid : Model -> Bool
isValid model = not
  (  (model.name /= "" && Just model.name == model.latin)
  || hasDuplicates (List.map (\v -> (v.vid, Maybe.withDefault "" v.rid)) model.vns)
  || not (Img.isValid model.image)
  || (model.mainHas && model.main /= Nothing && model.main == model.id)
  )


spoilOpts =
  [ (0, "Not a spoiler")
  , (1, "Minor spoiler")
  , (2, "Major spoiler")
  ]


view : Model -> Html Msg
view model =
  let
    geninfo =
      [ formField "name::Name (original)" [ inputText "name" model.name Name (onInvalid (Invalid General) :: GCE.valName) ]
      , if not (model.latin /= Nothing || containsNonLatin model.name) then text "" else
        formField "latin::Name (latin)"
        [ inputText "latin" (Maybe.withDefault "" model.latin) Latin (onInvalid (Invalid General) :: placeholder "Romanization" :: GCE.valLatin)
        , case model.latin of
            Just s -> if containsNonLatin s
                      then b [] [ br [] [], text "Romanization should only consist of characters in the latin alphabet." ] else text ""
            Nothing -> text ""
        ]
      , formField "alias::Aliases"
        [ inputTextArea "alias" model.alias Alias (rows 3 :: onInvalid (Invalid General) :: GCE.valAlias)
        , br [] []
        , text "(Un)official aliases, separated by a newline. Must not include spoilers!"
        ]
      , formField "desc::Description" [ TP.view "desc" model.description Desc 600 (style "height" "150px" :: onInvalid (Invalid General) :: GCE.valDescription)
        [ b [] [ text "English please!" ] ] ]
      , formField "bmonth::Birthday"
        [ inputSelect "bmonth" model.bMonth BMonth [style "width" "128px"] <| (0, "Unknown") :: RDate.monthSelect
        , if model.bMonth == 0 then text ""
          else inputSelect "" model.bDay BDay [style "width" "70px"] <| List.map (\i -> (i, String.fromInt i)) <| List.range 1 31
        ]
      , formField "age::Age" [ inputNumber "age" model.age Age (onInvalid (Invalid General) :: GCE.valAge), text " years" ]

      , tr [ class "newpart" ] [ td [ colspan 2 ] [ text "Body" ] ]
      , formField "gender::Sex"
        [ inputSelect "gender" model.gender Gender [] GT.genders
        , label [] [ inputCheck "" (isJust model.spoilGender) (\b -> SpoilGender <| if b then (Just "unknown") else Nothing), text " spoiler" ]
        , case model.spoilGender of
            Nothing -> text ""
            Just gen -> span []
              [ br [] []
              , text "▲ apparent (non-spoiler) sex"
              , br [] []
              , text "▼ actual (spoiler) sex"
              , br [] []
              , inputSelect "" gen (\s -> SpoilGender (Just s)) [] GT.genders
              ]
        ]
      , formField "sbust::Bust"    [ inputNumber "sbust"  (if model.sBust  == 0 then Nothing else Just model.sBust ) SBust  (onInvalid (Invalid General) :: GCE.valS_Bust), text " cm" ]
      , formField "swaist::Waist"  [ inputNumber "swiast" (if model.sWaist == 0 then Nothing else Just model.sWaist) SWaist (onInvalid (Invalid General) :: GCE.valS_Waist),text " cm" ]
      , formField "ship::Hips"     [ inputNumber "ship"   (if model.sHip   == 0 then Nothing else Just model.sHip  ) SHip   (onInvalid (Invalid General) :: GCE.valS_Hip),  text " cm" ]
      , formField "height::Height" [ inputNumber "height" (if model.height == 0 then Nothing else Just model.height) Height (onInvalid (Invalid General) :: GCE.valHeight), text " cm" ]
      , formField "weight::Weight" [ inputNumber "weight" model.weight Weight (onInvalid (Invalid General) :: GCE.valWeight), text " kg" ]
      , formField "bloodt::Blood type" [ inputSelect "bloodt"  model.bloodt  BloodT  [onInvalid (Invalid General)] GT.bloodTypes ]
      , formField "cupsize::Cup size"  [ inputSelect "cupsize" model.cupSize CupSize [onInvalid (Invalid General)] GT.cupSizes ]

      , tr [ class "newpart" ] [ td [ colspan 2 ] [ text "Instance" ] ]
      ] ++ if model.mainRef
      then
      [ formField "" [ text "This character is already used as an instance for another character. If you want to link more characters to this one, please edit the other characters instead." ] ]
      else
      [ formField "" [ label [] [ inputCheck "" model.mainHas MainHas, text " This character is an instance of another character." ] ]
      , formField "" <| if not model.mainHas then [] else
        [ inputSelect "" model.mainSpoil MainSpoil [] spoilOpts
        , br_ 2
        , Maybe.withDefault (text "No character selected") <| Maybe.map (\m -> span []
          [ text "Selected character: "
          , small [] [ text <| m ++ ": " ]
          , a [ href <| "/" ++ m ] [ text model.mainName ]
          , if Just m == model.id then b [] [ br [] [], text "A character can't be an instance of itself. Please select another character or disable the above checkbox to remove the instance." ] else text ""
          ]) model.main
        , br [] []
        , A.view mainConfig model.mainSearch [placeholder "Set character..."]
        ]
      ]

    image =
      table [ class "formimage" ] [ tr []
      [ td [] [ Img.viewImg model.image ]
      , td []
        [ h2 [] [ text "Image ID" ]
        , input ([ type_ "text", class "text", tabindex 10, value (Maybe.withDefault "" model.image.id), onInvalid (Invalid Image), onInputValidation ImageSet ] ++ GCE.valImage) []
        , br [] []
        , text "Use an image that already exists on the server or empty to remove the current image."
        , br_ 2
        , h2 [] [ text "Upload new image" ]
        , inputButton "Browse image" ImageSelect []
        , br [] []
        , text "Image must be in JPEG, PNG or WebP format and at most 10 MiB. Images larger than 256x300 will automatically be resized."
        , case Img.viewVote model.image ImageMsg (Invalid Image) of
            Nothing -> text ""
            Just v ->
              div []
              [ br [] []
              , text "Please flag this image: (see the ", a [ href "/d19" ] [ text "image flagging guidelines" ], text " for guidance)"
              , v
              ]
        ]
      ] ]

    traits =
      let
        old = List.filter (\(_,t) -> not t.new) <| List.indexedMap (\i t -> (i,t)) model.traits
        new = List.filter (\(_,t) ->     t.new) <| List.indexedMap (\i t -> (i,t)) model.traits
        spoil t = case model.traitSel of
                    (x,Spoil s) -> if t.tid == x then s else t.spoil
                    _ -> t.spoil
        lie t = case model.traitSel of
                    (x,Lie) -> if t.tid == x then True else t.lie
                    _ -> t.lie
        trait (i,t) = (t.tid,
          tr []
          [ td [ style "padding" "0 0 0 10px", style "text-decoration" (if t.applicable && not t.hidden then "none" else "line-through") ]
            [ Maybe.withDefault (text "") <| Maybe.map (\g -> small [] [ text <| g ++ " / " ]) t.group
            , a [ href <| "/" ++ t.tid ] [ text t.name ]
            , if t.hidden && not t.locked then b [] [ text " (awaiting moderation)" ]
              else if t.hidden then b [] [ text " (deleted)" ]
              else if not t.applicable then b [] [ text " (not applicable)" ]
              else text ""
            ]
          , td [ class "buts" ]
            [ a [ href "#", onMouseOver (TraitSel t.tid (Spoil 0)), onMouseOut (TraitSel "" (Spoil 0)), onClickD (TraitSpoil i 0), classList [("s0", spoil t == 0 )], title "Not a spoiler" ] []
            , a [ href "#", onMouseOver (TraitSel t.tid (Spoil 1)), onMouseOut (TraitSel "" (Spoil 0)), onClickD (TraitSpoil i 1), classList [("s1", spoil t == 1 )], title "Minor spoiler" ] []
            , a [ href "#", onMouseOver (TraitSel t.tid (Spoil 2)), onMouseOut (TraitSel "" (Spoil 0)), onClickD (TraitSpoil i 2), classList [("s2", spoil t == 2 )], title "Major spoiler" ] []
            , a [ href "#", onMouseOver (TraitSel t.tid Lie), onMouseOut (TraitSel "" (Spoil 0)), onClickD (TraitLie i (not t.lie)), classList [("sl", lie t)], title "Lie" ] []
            ]
          , td [ style "width" "150px", style "white-space" "nowrap" ]
            [ case (t.tid == Tuple.first model.traitSel, Tuple.second model.traitSel) of
                (True, Spoil 0) -> text "Not a spoiler"
                (True, Spoil 1) -> text "Minor spoiler"
                (True, Spoil 2) -> text "Major spoiler"
                (True, Lie)     -> text "This turns out to be false"
                _ -> a [ href "#", onClickD (TraitDel i)] [ text "remove" ]
            ]
          ])
      in
      K.node "table" [ class "formtable chare_traits" ] <|
        (if List.isEmpty old then []
         else ("head",  tr [ class "newpart" ] [ td [ colspan 3 ] [text "Current traits"     ]]) :: List.map trait old)
        ++
        (if List.isEmpty new then []
         else ("added", tr [ class "newpart" ] [ td [ colspan 3 ] [text "Newly added traits" ]]) :: List.map trait new)
        ++
        [ ("add", tr [] [ td [ colspan 3 ] [ br_ 1, A.view traitConfig model.traitSearch [placeholder "Add trait..."] ] ])
        ]

    -- XXX: This function has quite a few nested loops, prolly rather slow with many VNs/releases
    vns =
      let
        uniq lst set =
          case lst of
            (x::xs) -> if Set.member x set then uniq xs set else x :: uniq xs (Set.insert x set)
            [] -> []
        vn vid lst rels =
          let title = Maybe.withDefault "<unknown>" <| Maybe.map (\(_,v) -> v.title) <| List.head lst
          in
          [ ( vid
            , tr [ class "newpart" ] [ td [ colspan 4, style "padding-bottom" "5px" ]
              [ small [] [ text <| vid ++ ":" ]
              , a [ href <| "/" ++ vid ] [ text title ]
              ]]
            )
          ] ++ List.map (\(idx,item) ->
            ( vid ++ "i" ++ Maybe.withDefault "r0" item.rid
            , tr []
              [ td [] [ inputSelect "" item.rid (VnRel idx) [ style "width" "400px", style "margin" "0 15px" ] <|
                  (Nothing, if List.length lst == 1 then "All (full) releases" else "Other releases")
                  :: List.map (\r -> (Just r.id, RDate.showrel r)) rels
                  ++ if isJust item.rid && List.isEmpty (List.filter (\r -> Just r.id == item.rid) rels)
                     then [(item.rid, "Deleted release: " ++ Maybe.withDefault "" item.rid)] else []
                ]
              , td [] [ inputSelect "" item.role (VnRole idx) [] GT.charRoles ]
              , td [] [ inputSelect "" item.spoil (VnSpoil idx) [ style "width" "130px", style "margin" "0 5px" ] spoilOpts ]
              , td [] [ inputButton "remove" (VnDel idx) [] ]
              ]
            )
          ) lst
          ++ (if List.map (\(_,r) -> Maybe.withDefault "" r.rid) lst |> hasDuplicates |> not then [] else [
            ( vid ++ "dup"
            , td [] [ td [ colspan 4, style "padding" "0 15px" ] [ b [] [ text "List contains duplicate releases." ] ] ]
            )
          ])
          ++ (if 1 /= List.length (List.filter (\(_,r) -> isJust r.rid) lst) then [] else [
            ( vid ++ "warn"
            , tr [] [ td [ colspan 4, style "padding" "0 15px" ]
              [ b [] [ text "Note: " ]
              , text "Only select specific releases if the character has a significantly different role in those releases. "
              , br [] []
              , text "If the character's role is mostly the same in all releases (ignoring trials), then just select \"All (full) releases\"." ]
            ])
          ])
          ++ (if List.length lst > List.length rels then [] else [
            ( vid ++ "add"
            , tr [] [ td [ colspan 4 ] [ inputButton "add release" (VnRelAdd vid title) [style "margin" "0 15px"] ] ]
            )
          ])
      in
      K.node "table" [ class "formtable" ] <|
        List.concatMap
          (\vid -> vn vid (List.filter (\(_,r) -> r.vid == vid) (List.indexedMap (\i r -> (i,r)) model.vns)) (Maybe.withDefault [] (Dict.get vid model.releases)))
          (uniq (List.map (\v -> v.vid) model.vns) Set.empty)
        ++
        [ ("add", tr [] [ td [ colspan 4 ] [ br_ 1, A.view vnConfig model.vnSearch [placeholder "Add visual novel..."] ] ]) ]

  in
  form_ "mainform" Submit (model.state == Api.Loading)
  [ nav []
    [ menu []
      [ li [ classList [("tabselected", model.tab == General)] ] [ a [ href "#", onClickD (Tab General) ] [ text "General info" ] ]
      , li [ classList [("tabselected", model.tab == Image  )] ] [ a [ href "#", onClickD (Tab Image  ) ] [ text "Image"        ] ]
      , li [ classList [("tabselected", model.tab == Traits )] ] [ a [ href "#", onClickD (Tab Traits ) ] [ text "Traits"       ] ]
      , li [ classList [("tabselected", model.tab == VNs    )] ] [ a [ href "#", onClickD (Tab VNs    ) ] [ text "Visual Novels"] ]
      , li [ classList [("tabselected", model.tab == All    )] ] [ a [ href "#", onClickD (Tab All    ) ] [ text "All items"    ] ]
      ]
    ]
  , article [ classList [("hidden", model.tab /= General && model.tab /= All)] ] [ h1 [] [ text "General info" ], table [ class "formtable" ] geninfo ]
  , article [ classList [("hidden", model.tab /= Image   && model.tab /= All)] ] [ h1 [] [ text "Image" ], image ]
  , article [ classList [("hidden", model.tab /= Traits  && model.tab /= All)] ] [ h1 [] [ text "Traits" ], traits ]
  , article [ classList [("hidden", model.tab /= VNs     && model.tab /= All)] ] [ h1 [] [ text "Visual Novels" ], vns ]
  , article [] [ fieldset [ class "submit" ]
      [ Html.map Editsum (Editsum.view model.editsum)
      , submitButton "Submit" model.state (isValid model)
      ]
    ]
  ]
