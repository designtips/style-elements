module Internal.Model exposing (..)

{-| Implement style elements using as few calls as possible
-}

import Color exposing (Color)
import Html exposing (Html)
import Html.Attributes
import Internal.Style
import Json.Encode as Json
import Regex
import Set exposing (Set)
import VirtualCss
import VirtualDom


type Element msg
    = Unstyled (LayoutContext -> Html msg)
    | Styled
        { styles : List Style
        , html : Maybe String -> LayoutContext -> Html msg

        -- , node : NodeName
        -- , attributes : List (Html.Attribute msg)
        -- , children : List (Element msg)
        }



-- | Unresolved (List Style) NodeName (List (Html.Attribute msg)) (List (Html msg))


type LayoutContext
    = AsRow
    | AsColumn
    | AsEl


asRow =
    AsRow


asColumn =
    AsColumn


asEl =
    AsEl


type Aligned
    = Unaligned
    | Aligned (Maybe HAlign) (Maybe VAlign)


type HAlign
    = Left
    | CenterX
    | Right


type VAlign
    = Top
    | CenterY
    | Bottom


type Style
    = Style String (List Property)
      --       class  prop   val
    | Single String String String
    | Colored String String Color
    | SpacingStyle Int Int
    | PaddingStyle Int Int Int Int


type Property
    = Property String String


type Attribute msg
    = Attr (Html.Attribute msg)
      -- invalidation key and literal class
    | Class String String
      -- invalidation key "border-color" as opposed to "border-color-10-10-10" that will be the key for the class
    | StyleClass Style
      -- Descriptions will add aria attributes and if the element is not a link, may set the node type.
    | AlignY VAlign
    | AlignX HAlign
    | Describe Description
    | Nearby Location (Element msg)
    | Move (Maybe Float) (Maybe Float) (Maybe Float)
    | Rotate Float Float Float Float
    | Scale (Maybe Float) (Maybe Float) (Maybe Float)
    | TextShadow
        { offset : ( Float, Float )
        , blur : Float
        , color : Color
        }
    | BoxShadow
        { inset : Bool
        , offset : ( Float, Float )
        , size : Float
        , blur : Float
        , color : Color
        }
    | Filter FilterType
    | NoAttribute


type Description
    = Main
    | Navigation
      -- | Search
    | ContentInfo
    | Complementary
    | Heading Int
    | Label String
    | LivePolite
    | LiveAssertive


type FilterType
    = FilterUrl String
    | Blur Float
    | Brightness Float
    | Contrast Float
    | Grayscale Float
    | HueRotate Float
    | Invert Float
    | OpacityFilter Float
    | Saturate Float
    | Sepia Float
    | DropShadow
        { offset : ( Float, Float )
        , size : Float
        , blur : Float
        , color : Color
        }


type Length
    = Px Float
    | Content
    | Fill Float


type Axis
    = XAxis
    | YAxis
    | AllAxis


type Location
    = Above
    | Below
    | OnRight
    | OnLeft
    | Overlay


map : (msg -> msg1) -> Element msg -> Element msg1
map fn el =
    case el of
        Styled styled ->
            Styled
                { styles = styled.styles
                , html = \add context -> Html.map fn <| styled.html add context

                -- , node = styled.node
                -- , attributes = List.map (Html.Attributes.map fn) styled.attributes
                -- , children = List.map (map fn) styled.children
                }

        Unstyled html ->
            Unstyled (Html.map fn << html)


mapAttr : (msg -> msg1) -> Attribute msg -> Attribute msg1
mapAttr fn attr =
    case attr of
        NoAttribute ->
            NoAttribute

        Describe description ->
            Describe description

        AlignX x ->
            AlignX x

        AlignY y ->
            AlignY y

        -- invalidation key "border-color" as opposed to "border-color-10-10-10" that will be the key for the class
        Class x y ->
            Class x y

        StyleClass style ->
            StyleClass style

        Nearby location element ->
            Nearby location (map fn element)

        Move x y z ->
            Move x y z

        Rotate x y z a ->
            Rotate x y z a

        Scale x y z ->
            Scale x y z

        Attr htmlAttr ->
            Attr (Html.Attributes.map fn htmlAttr)

        TextShadow shadow ->
            TextShadow shadow

        BoxShadow shadow ->
            BoxShadow shadow

        Filter filter ->
            Filter filter


class : String -> Attribute msg
class x =
    Class x x


{-| -}
embed : (a -> Element msg) -> a -> LayoutContext -> Html msg
embed fn a =
    case fn a of
        Unstyled html ->
            html

        Styled styled ->
            styled.html (Just (toStyleSheetString styled.styles))


{-| -}
unstyled : Html msg -> Element msg
unstyled =
    Unstyled << always


renderNode : Aligned -> NodeName -> List (VirtualDom.Property msg) -> List (VirtualDom.Node msg) -> Maybe String -> LayoutContext -> VirtualDom.Node msg
renderNode alignment node attrs children styles context =
    let
        html =
            case node of
                Generic ->
                    VirtualDom.node "div"
                        attrs
                        (case styles of
                            Nothing ->
                                children

                            Just stylesheet ->
                                children ++ [ VirtualDom.node "style" [] [ Html.text stylesheet ] ]
                        )

                NodeName nodeName ->
                    VirtualDom.node nodeName
                        attrs
                        (case styles of
                            Nothing ->
                                children

                            Just stylesheet ->
                                children ++ [ VirtualDom.node "style" [] [ Html.text stylesheet ] ]
                        )

                Embedded nodeName internal ->
                    VirtualDom.node nodeName
                        attrs
                        [ VirtualDom.node internal
                            [ Html.Attributes.class "se el" ]
                            (case styles of
                                Nothing ->
                                    children

                                Just stylesheet ->
                                    children ++ [ VirtualDom.node "style" [] [ Html.text stylesheet ] ]
                            )
                        ]
    in
    case context of
        AsEl ->
            html

        AsRow ->
            case alignment of
                Unaligned ->
                    html

                Aligned (Just Left) _ ->
                    VirtualDom.node "alignLeft"
                        [ Html.Attributes.class "se el container align-container-left" ]
                        [ html ]

                Aligned (Just Right) _ ->
                    VirtualDom.node "alignRight"
                        [ Html.Attributes.class "se el container align-container-right" ]
                        [ html ]

                _ ->
                    html

        AsColumn ->
            case alignment of
                Unaligned ->
                    html

                Aligned _ (Just Top) ->
                    VirtualDom.node "alignTop"
                        [ Html.Attributes.class "se el container align-container-top" ]
                        [ html ]

                Aligned _ (Just Bottom) ->
                    VirtualDom.node "alignBottom"
                        [ Html.Attributes.class "se el container align-container-bottom" ]
                        [ html ]

                _ ->
                    html


addNodeName : String -> NodeName -> NodeName
addNodeName newNode old =
    case old of
        Generic ->
            NodeName newNode

        NodeName name ->
            Embedded name newNode

        Embedded x y ->
            Embedded x y


alignXName align =
    case align of
        Left ->
            "self-left"

        Right ->
            "self-right"

        CenterX ->
            "self-center-x"


alignYName align =
    case align of
        Top ->
            "self-top"

        Bottom ->
            "self-bottom"

        CenterY ->
            "self-center-y"


gatherAttributes : Attribute msg -> Gathered msg -> Gathered msg
gatherAttributes attr gathered =
    case attr of
        NoAttribute ->
            gathered

        Describe description ->
            case description of
                Main ->
                    { gathered | node = addNodeName "main" gathered.node }

                Navigation ->
                    { gathered | node = addNodeName "nav" gathered.node }

                -- Search ->
                --     { gathered | node = addNodeName "main" gathered.node }
                ContentInfo ->
                    { gathered | node = addNodeName "footer" gathered.node }

                Complementary ->
                    { gathered | node = addNodeName "aside" gathered.node }

                Heading i ->
                    if i < 1 then
                        { gathered | node = addNodeName "h1" gathered.node }
                    else if i < 7 then
                        { gathered | node = addNodeName ("h" ++ toString i) gathered.node }
                    else
                        { gathered | node = addNodeName "h6" gathered.node }

                Label label ->
                    { gathered | attributes = Html.Attributes.attribute "aria-label" label :: gathered.attributes }

                LivePolite ->
                    { gathered | attributes = Html.Attributes.attribute "aria-live" "polite" :: gathered.attributes }

                LiveAssertive ->
                    { gathered | attributes = Html.Attributes.attribute "aria-live" "assertive" :: gathered.attributes }

        Nearby location elem ->
            case elem of
                Unstyled html ->
                    { gathered
                        | nearbys =
                            VirtualDom.node "div" [ Html.Attributes.class (locationClass location) ] [ html asEl ]
                                :: gathered.nearbys
                    }

                Styled styled ->
                    { gathered
                        | styles = gathered.styles ++ styled.styles
                        , nearbys =
                            VirtualDom.node "div"
                                [ Html.Attributes.class (locationClass location) ]
                                [ styled.html Nothing asEl
                                ]
                                :: gathered.nearbys
                    }

        StyleClass style ->
            { gathered
                | attributes = VirtualDom.property "className" (Json.string (styleName style)) :: gathered.attributes
                , styles = addDot style :: gathered.styles
                , has = Set.insert (styleKey style) gathered.has
            }

        AlignX x ->
            case gathered.alignment of
                Unaligned ->
                    let
                        class =
                            alignXName x
                    in
                    { gathered
                        | attributes = VirtualDom.property "className" (Json.string class) :: gathered.attributes
                        , alignment = Aligned (Just x) Nothing
                    }

                Aligned (Just _) _ ->
                    gathered

                Aligned _ y ->
                    let
                        class =
                            alignXName x
                    in
                    { gathered
                        | attributes = VirtualDom.property "className" (Json.string class) :: gathered.attributes
                        , alignment = Aligned (Just x) y
                    }

        AlignY y ->
            case gathered.alignment of
                Unaligned ->
                    let
                        class =
                            alignYName y
                    in
                    { gathered
                        | attributes = VirtualDom.property "className" (Json.string class) :: gathered.attributes
                        , alignment = Aligned Nothing (Just y)
                    }

                Aligned _ (Just _) ->
                    gathered

                Aligned x _ ->
                    let
                        class =
                            alignYName y
                    in
                    { gathered
                        | attributes = VirtualDom.property "className" (Json.string class) :: gathered.attributes
                        , alignment = Aligned x (Just y)
                    }

        Class key class ->
            if Set.member key gathered.has then
                gathered
            else
                { gathered
                    | attributes = VirtualDom.property "className" (Json.string class) :: gathered.attributes
                    , has = Set.insert key gathered.has
                }

        Attr attr ->
            { gathered | attributes = attr :: gathered.attributes }

        Move mx my mz ->
            -- add translate to the transform stack
            let
                addIfNothing val existing =
                    case existing of
                        Nothing ->
                            val

                        x ->
                            x

                translate =
                    case gathered.translation of
                        Nothing ->
                            Just
                                ( mx, my, mz )

                        Just ( existingX, existingY, existingZ ) ->
                            Just
                                ( addIfNothing mx existingX
                                , addIfNothing my existingY
                                , addIfNothing mz existingZ
                                )
            in
            { gathered | translation = translate }

        Filter filter ->
            case gathered.filters of
                Nothing ->
                    { gathered | filters = Just (filterName filter) }

                Just existing ->
                    { gathered | filters = Just (filterName filter ++ " " ++ existing) }

        BoxShadow shadow ->
            case gathered.boxShadows of
                Nothing ->
                    { gathered | boxShadows = Just (formatBoxShadow shadow) }

                Just existing ->
                    { gathered | boxShadows = Just (formatBoxShadow shadow ++ ", " ++ existing) }

        TextShadow shadow ->
            case gathered.textShadows of
                Nothing ->
                    { gathered | textShadows = Just (formatTextShadow shadow) }

                Just existing ->
                    { gathered | textShadows = Just (formatTextShadow shadow ++ ", " ++ existing) }

        Rotate x y z angle ->
            { gathered
                | rotation =
                    Just
                        ("rotate3d(" ++ toString x ++ "," ++ toString y ++ "," ++ toString z ++ "," ++ toString angle ++ "rad)")
            }

        Scale mx my mz ->
            -- add scale to the transform stack
            let
                addIfNothing val existing =
                    case existing of
                        Nothing ->
                            val

                        x ->
                            x

                scale =
                    case gathered.scale of
                        Nothing ->
                            Just
                                ( mx
                                , my
                                , mz
                                )

                        Just ( existingX, existingY, existingZ ) ->
                            Just
                                ( addIfNothing mx existingX
                                , addIfNothing my existingY
                                , addIfNothing mz existingZ
                                )
            in
            { gathered | scale = scale }


type NodeName
    = Generic
    | NodeName String
    | Embedded String String


type alias Gathered msg =
    { attributes : List (Html.Attribute msg)
    , styles : List Style
    , alignment : Aligned
    , nearbys : List (Html msg)
    , node : NodeName
    , filters : Maybe String
    , boxShadows : Maybe String
    , textShadows : Maybe String
    , rotation : Maybe String
    , translation : Maybe ( Maybe Float, Maybe Float, Maybe Float )
    , scale : Maybe ( Maybe Float, Maybe Float, Maybe Float )
    , has : Set String
    }


pair =
    (,)


initGathered : Maybe String -> List Style -> Gathered msg
initGathered maybeNodeName styles =
    { attributes = []
    , styles = styles
    , alignment = Unaligned
    , node =
        case maybeNodeName of
            Nothing ->
                Generic

            Just name ->
                NodeName name
    , nearbys = []
    , rotation = Nothing
    , translation = Nothing
    , scale = Nothing
    , filters = Nothing
    , boxShadows = Nothing
    , textShadows = Nothing
    , has = Set.empty
    }


{-| -}
uncapitalize : String -> String
uncapitalize str =
    let
        head =
            String.left 1 str
                |> String.toLower

        tail =
            String.dropLeft 1 str
    in
    head ++ tail


{-| -}
className : String -> String
className x =
    x
        |> uncapitalize
        |> Regex.replace Regex.All (Regex.regex "[^a-zA-Z0-9_-]") (\_ -> "")
        |> Regex.replace Regex.All (Regex.regex "[A-Z0-9]+") (\{ match } -> " " ++ String.toLower match)
        |> Regex.replace Regex.All (Regex.regex "[\\s+]") (\_ -> "")


formatTransformations : Gathered msg -> Gathered msg
formatTransformations gathered =
    let
        translate =
            case gathered.translation of
                Nothing ->
                    Nothing

                Just ( x, y, z ) ->
                    Just
                        ("translate3d("
                            ++ toString (Maybe.withDefault 0 x)
                            ++ "px, "
                            ++ toString (Maybe.withDefault 0 y)
                            ++ "px, "
                            ++ toString (Maybe.withDefault 0 z)
                            ++ "px)"
                        )

        scale =
            case gathered.scale of
                Nothing ->
                    Nothing

                Just ( x, y, z ) ->
                    Just
                        ("scale3d("
                            ++ toString (Maybe.withDefault 0 x)
                            ++ "px, "
                            ++ toString (Maybe.withDefault 0 y)
                            ++ "px, "
                            ++ toString (Maybe.withDefault 0 z)
                            ++ "px)"
                        )

        transformations =
            [ scale, translate, gathered.rotation ]
                |> List.filterMap identity

        addTransform ( classes, styles ) =
            case transformations of
                [] ->
                    ( classes, styles )

                trans ->
                    let
                        transforms =
                            String.join " " trans

                        name =
                            "transform-" ++ className transforms
                    in
                    ( name :: classes
                    , Single ("." ++ name) "transform" transforms
                        :: styles
                    )

        addFilters ( classes, styles ) =
            case gathered.filters of
                Nothing ->
                    ( classes, styles )

                Just filter ->
                    let
                        name =
                            "filter-" ++ className filter
                    in
                    ( name :: classes
                    , Single ("." ++ name) "filter" filter
                        :: styles
                    )

        addBoxShadows ( classes, styles ) =
            case gathered.boxShadows of
                Nothing ->
                    ( classes, styles )

                Just shades ->
                    let
                        name =
                            "box-shadow-" ++ className shades
                    in
                    ( name :: classes
                    , Single ("." ++ name) "box-shadow" shades
                        :: styles
                    )

        addTextShadows ( classes, styles ) =
            case gathered.textShadows of
                Nothing ->
                    ( classes, styles )

                Just shades ->
                    let
                        name =
                            "text-shadow-" ++ className shades
                    in
                    ( name :: classes
                    , Single ("." ++ name) "text-shadow" shades
                        :: styles
                    )
    in
    let
        ( classes, styles ) =
            ( [], gathered.styles )
                |> addFilters
                |> addBoxShadows
                |> addTextShadows
                |> addTransform
    in
    { gathered
        | styles = styles
        , attributes =
            Html.Attributes.class (String.join " " classes) :: gathered.attributes
    }


renderAttributes : Maybe String -> List Style -> List (Attribute msg) -> Gathered msg
renderAttributes node styles attributes =
    case attributes of
        [] ->
            initGathered node styles

        attrs ->
            List.foldr gatherAttributes (initGathered node styles) attrs
                |> formatTransformations


element : LayoutContext -> Maybe String -> List (Attribute msg) -> List (Element msg) -> Element msg
element context nodeName attributes children =
    let
        -- htmlChildren =
        --     List.foldr gather [] children
        -- gather child htmls =
        --     case child of
        --         Unstyled html ->
        --             html context :: htmls
        --         Styled styled ->
        --             styled.html Nothing context :: htmls
        -- rendered =
        --     renderAttributes nodeName [] attributes
        ( htmlChildren, styleChildren ) =
            List.foldr gather ( [], [] ) children

        gather child ( htmls, existingStyles ) =
            case child of
                Unstyled html ->
                    ( html context :: htmls
                    , existingStyles
                    )

                Styled styled ->
                    ( styled.html Nothing context :: htmls
                    , styled.styles ++ existingStyles
                    )

        rendered =
            renderAttributes nodeName styleChildren attributes
    in
    case rendered.styles of
        [] ->
            Unstyled <| renderNode rendered.alignment rendered.node rendered.attributes htmlChildren Nothing

        _ ->
            Styled
                { styles = rendered.styles
                , html = renderNode rendered.alignment rendered.node rendered.attributes htmlChildren

                -- , children = children
                }


type RenderMode
    = Viewport
    | Layout
    | NoStaticStyleSheet
    | WithVirtualCss
    | Unreduced



-- renderStyles : Element msg -> ( Set String, List Style ) -> ( Set String, List Style )
-- renderStyles el ( cache, existing ) =
--     case el of
--         Unstyled html ->
--             ( cache, existing )
--         Styled styled ->
--             let
--                 reduced =
--                     List.foldr reduceStyles ( cache, existing ) styled.styles
--             in
--             List.foldr renderStyles reduced styled.children


{-| -}
renderRoot : RenderMode -> List (Attribute msg) -> Element msg -> Html msg
renderRoot mode attributes child =
    let
        ( htmlChildren, styleChildren ) =
            case child of
                Unstyled html ->
                    ( html asEl, [] )

                Styled styled ->
                    ( styled.html Nothing asEl, styled.styles )

        rendered =
            renderAttributes Nothing styleChildren attributes

        styles =
            rendered.styles
                |> List.foldr reduceStyles ( Set.empty, [] )
                -- |> renderStyles child
                |> Tuple.second

        styleSheets children =
            case mode of
                NoStaticStyleSheet ->
                    toStyleSheet styles :: children

                Layout ->
                    Internal.Style.rulesElement
                        :: toStyleSheet styles
                        :: children

                Viewport ->
                    Internal.Style.viewportRulesElement
                        :: toStyleSheet styles
                        :: children

                Unreduced ->
                    Internal.Style.rulesElement
                        :: toStyleSheetNoReduction styles
                        :: children

                WithVirtualCss ->
                    let
                        _ =
                            toStyleSheetVirtualCss styles
                    in
                    Internal.Style.rulesElement
                        :: children

        children =
            case rendered.nearbys of
                [] ->
                    styleSheets [ htmlChildren ]

                additional ->
                    styleSheets <|
                        htmlChildren
                            :: [ VirtualDom.node "div"
                                    [ VirtualDom.property "className" (Json.string "se el nearby") ]
                                    additional
                               ]
    in
    renderNode rendered.alignment rendered.node rendered.attributes children Nothing asEl


htmlClass : String -> Attribute msg
htmlClass cls =
    Attr <| VirtualDom.property "className" (Json.string cls)


reduceStyles : Style -> ( Set String, List Style ) -> ( Set String, List Style )
reduceStyles style ( cache, existing ) =
    case style of
        Style selector props ->
            ( cache, existing )

        Single class prop val ->
            if Set.member class cache then
                ( cache, existing )
            else
                ( Set.insert class cache
                , style :: existing
                )

        Colored class prop color ->
            if Set.member class cache then
                ( cache, existing )
            else
                ( Set.insert class cache
                , style :: existing
                )

        SpacingStyle x y ->
            let
                class =
                    ".spacing-" ++ toString x ++ "-" ++ toString y
            in
            if Set.member class cache then
                ( cache, existing )
            else
                ( Set.insert class cache
                , style :: existing
                )

        PaddingStyle top right bottom left ->
            let
                class =
                    ".pad-"
                        ++ toString top
                        ++ "-"
                        ++ toString right
                        ++ "-"
                        ++ toString bottom
                        ++ "-"
                        ++ toString left
            in
            if Set.member class cache then
                ( cache, existing )
            else
                ( Set.insert class cache
                , style :: existing
                )


toStyleSheetString : List Style -> String
toStyleSheetString stylesheet =
    let
        renderProps (Property key val) existing =
            existing ++ "\n  " ++ key ++ ": " ++ val ++ ";"

        renderStyle selector props =
            selector ++ "{" ++ List.foldl renderProps "" props ++ "\n}"

        combine style rendered =
            case style of
                Style selector props ->
                    rendered ++ "\n" ++ renderStyle selector props

                Single class prop val ->
                    rendered ++ class ++ "{" ++ prop ++ ":" ++ val ++ "}\n"

                Colored class prop color ->
                    rendered ++ class ++ "{" ++ prop ++ ":" ++ formatColor color ++ "}\n"

                SpacingStyle x y ->
                    let
                        class =
                            ".spacing-" ++ toString x ++ "-" ++ toString y
                    in
                    rendered ++ spacingClasses class x y

                PaddingStyle top right bottom left ->
                    let
                        class =
                            ".pad-"
                                ++ toString top
                                ++ "-"
                                ++ toString right
                                ++ "-"
                                ++ toString bottom
                                ++ "-"
                                ++ toString left
                    in
                    rendered
                        ++ renderStyle class
                            [ Property "padding"
                                (toString top
                                    ++ "px "
                                    ++ toString right
                                    ++ "px "
                                    ++ toString bottom
                                    ++ "px "
                                    ++ toString left
                                    ++ "px"
                                )
                            ]
    in
    List.foldl combine "" stylesheet


toStyleSheet : List Style -> VirtualDom.Node msg
toStyleSheet stylesheet =
    case stylesheet of
        [] ->
            Html.text ""

        styles ->
            let
                renderProps (Property key val) existing =
                    existing ++ "\n  " ++ key ++ ": " ++ val ++ ";"

                renderStyle selector props =
                    selector ++ "{" ++ List.foldl renderProps "" props ++ "\n}"

                combine style rendered =
                    case style of
                        Style selector props ->
                            rendered ++ "\n" ++ renderStyle selector props

                        Single class prop val ->
                            rendered ++ class ++ "{" ++ prop ++ ":" ++ val ++ "}\n"

                        Colored class prop color ->
                            rendered ++ class ++ "{" ++ prop ++ ":" ++ formatColor color ++ "}\n"

                        SpacingStyle x y ->
                            let
                                class =
                                    ".spacing-" ++ toString x ++ "-" ++ toString y
                            in
                            rendered ++ spacingClasses class x y

                        PaddingStyle top right bottom left ->
                            let
                                class =
                                    ".pad-"
                                        ++ toString top
                                        ++ "-"
                                        ++ toString right
                                        ++ "-"
                                        ++ toString bottom
                                        ++ "-"
                                        ++ toString left
                            in
                            rendered
                                ++ renderStyle class
                                    [ Property "padding"
                                        (toString top
                                            ++ "px "
                                            ++ toString right
                                            ++ "px "
                                            ++ toString bottom
                                            ++ "px "
                                            ++ toString left
                                            ++ "px"
                                        )
                                    ]
            in
            List.foldl combine "" styles
                |> (\rendered -> VirtualDom.node "style" [] [ Html.text rendered ])


spacingClasses : String -> Int -> Int -> String
spacingClasses class x y =
    let
        renderProps (Property key val) existing =
            existing ++ "\n  " ++ key ++ ": " ++ val ++ ";"

        renderStyle selector props =
            selector ++ "{" ++ List.foldl renderProps "" props ++ "\n}"

        merge ( selector, props ) existing =
            existing ++ "\n" ++ renderStyle selector props
    in
    List.foldl merge
        ""
        [ pair (class ++ ".row > .se") [ Property "margin-left" (toString x ++ "px") ]
        , pair (class ++ ".column > .se") [ Property "margin-top" (toString y ++ "px") ]
        , pair (class ++ ".page > .se") [ Property "margin-top" (toString y ++ "px") ]
        , pair (class ++ ".page > .self-left") [ Property "margin-right" (toString x ++ "px") ]
        , pair (class ++ ".page > .self-right") [ Property "margin-left" (toString x ++ "px") ]
        ]


formatDropShadow : { d | blur : a, color : Color, offset : ( b, c ) } -> String
formatDropShadow shadow =
    String.join " "
        [ toString (Tuple.first shadow.offset) ++ "px"
        , toString (Tuple.second shadow.offset) ++ "px"
        , toString shadow.blur ++ "px"
        , formatColor shadow.color
        ]


formatTextShadow : { d | blur : a, color : Color, offset : ( b, c ) } -> String
formatTextShadow shadow =
    String.join " "
        [ toString (Tuple.first shadow.offset) ++ "px"
        , toString (Tuple.second shadow.offset) ++ "px"
        , toString shadow.blur ++ "px"
        , formatColor shadow.color
        ]


formatBoxShadow : { e | blur : a, color : Color, inset : Bool, offset : ( b, c ), size : d } -> String
formatBoxShadow shadow =
    String.join " " <|
        List.filterMap identity
            [ if shadow.inset then
                Just "inset"
              else
                Nothing
            , Just <| toString (Tuple.first shadow.offset) ++ "px"
            , Just <| toString (Tuple.second shadow.offset) ++ "px"
            , Just <| toString shadow.blur ++ "px"
            , Just <| toString shadow.size ++ "px"
            , Just <| formatColor shadow.color
            ]


filterName filtr =
    case filtr of
        FilterUrl url ->
            "url(" ++ url ++ ")"

        Blur x ->
            "blur(" ++ toString x ++ "px)"

        Brightness x ->
            "brightness(" ++ toString x ++ "%)"

        Contrast x ->
            "contrast(" ++ toString x ++ "%)"

        Grayscale x ->
            "grayscale(" ++ toString x ++ "%)"

        HueRotate x ->
            "hueRotate(" ++ toString x ++ "deg)"

        Invert x ->
            "invert(" ++ toString x ++ "%)"

        OpacityFilter x ->
            "opacity(" ++ toString x ++ "%)"

        Saturate x ->
            "saturate(" ++ toString x ++ "%)"

        Sepia x ->
            "sepia(" ++ toString x ++ "%)"

        DropShadow shadow ->
            let
                shadowModel =
                    { offset = shadow.offset
                    , size = shadow.size
                    , blur = shadow.blur
                    , color = shadow.color
                    }
            in
            "drop-shadow(" ++ formatDropShadow shadowModel ++ ")"


floatClass : Float -> String
floatClass x =
    toString <| round (x * 100)


formatColor : Color -> String
formatColor color =
    let
        { red, green, blue, alpha } =
            Color.toRgb color
    in
    ("rgba(" ++ toString red)
        ++ ("," ++ toString green)
        ++ ("," ++ toString blue)
        ++ ("," ++ toString alpha ++ ")")


formatColorClass : Color -> String
formatColorClass color =
    let
        { red, green, blue, alpha } =
            Color.toRgb color
    in
    toString red
        ++ "-"
        ++ toString green
        ++ "-"
        ++ toString blue
        ++ "-"
        ++ floatClass alpha


toStyleSheetNoReduction : List Style -> VirtualDom.Node msg
toStyleSheetNoReduction styles =
    let
        renderProps (Property key val) existing =
            existing ++ "\n  " ++ key ++ ": " ++ val ++ ";"

        renderStyle selector props =
            selector ++ "{" ++ List.foldl renderProps "" props ++ "\n}"

        combine style rendered =
            case style of
                Style selector props ->
                    rendered ++ "\n" ++ renderStyle selector props

                Single class prop val ->
                    rendered ++ class ++ "{" ++ prop ++ ":" ++ val ++ "}\n"

                Colored class prop color ->
                    rendered ++ class ++ "{" ++ prop ++ ":" ++ formatColor color ++ "}\n"

                SpacingStyle x y ->
                    ""

                PaddingStyle top right bottom left ->
                    ""
    in
    List.foldl combine "" styles
        |> (\rendered -> VirtualDom.node "style" [] [ Html.text rendered ])


toStyleSheetVirtualCss : List Style -> ()
toStyleSheetVirtualCss stylesheet =
    case stylesheet of
        [] ->
            ()

        styles ->
            let
                renderProps (Property key val) existing =
                    existing ++ "\n  " ++ key ++ ": " ++ val ++ ";"

                renderStyle selector props =
                    selector ++ "{" ++ List.foldl renderProps "" props ++ "\n}"

                _ =
                    VirtualCss.clear ()

                combine style cache =
                    case style of
                        Style selector props ->
                            let
                                _ =
                                    VirtualCss.insert (renderStyle selector props) 0
                            in
                            cache

                        Single class prop val ->
                            if Set.member class cache then
                                cache
                            else
                                let
                                    _ =
                                        VirtualCss.insert (class ++ "{" ++ prop ++ ":" ++ val ++ "}") 0
                                in
                                Set.insert class cache

                        Colored class prop color ->
                            if Set.member class cache then
                                cache
                            else
                                let
                                    _ =
                                        VirtualCss.insert (class ++ "{" ++ prop ++ ":" ++ formatColor color ++ "}") 0
                                in
                                Set.insert class cache

                        SpacingStyle x y ->
                            let
                                class =
                                    ".spacing-" ++ toString x ++ "-" ++ toString y
                            in
                            if Set.member class cache then
                                cache
                            else
                                -- TODO!
                                cache

                        -- ( rendered ++ spacingClasses class x y
                        -- , Set.insert class cache
                        -- )
                        PaddingStyle top right bottom left ->
                            let
                                class =
                                    ".pad-"
                                        ++ toString top
                                        ++ "-"
                                        ++ toString right
                                        ++ "-"
                                        ++ toString bottom
                                        ++ "-"
                                        ++ toString left
                            in
                            if Set.member class cache then
                                cache
                            else
                                -- TODO!
                                cache

                -- ( rendered ++ paddingClasses class top right bottom left
                -- , Set.insert class cache
                -- )
            in
            List.foldl combine Set.empty styles
                |> always ()


styleKey : Style -> String
styleKey style =
    case style of
        Style class _ ->
            class

        Single _ prop _ ->
            prop

        Colored _ prop _ ->
            prop

        SpacingStyle _ _ ->
            "spacing"

        PaddingStyle _ _ _ _ ->
            "padding"


styleName : Style -> String
styleName style =
    case style of
        Style class _ ->
            class

        Single class _ _ ->
            class

        Colored class _ _ ->
            class

        SpacingStyle x y ->
            "spacing-" ++ toString x ++ "-" ++ toString y

        PaddingStyle top right bottom left ->
            "pad-"
                ++ toString top
                ++ "-"
                ++ toString right
                ++ "-"
                ++ toString bottom
                ++ "-"
                ++ toString left


addDot : Style -> Style
addDot style =
    case style of
        Style class props ->
            Style ("." ++ class) props

        Single class name val ->
            Single ("." ++ class) name val

        Colored class name val ->
            Colored ("." ++ class) name val

        SpacingStyle x y ->
            SpacingStyle x y

        PaddingStyle top right bottom left ->
            PaddingStyle top right bottom left


locationClass : Location -> String
locationClass location =
    case location of
        Above ->
            "se el above"

        Below ->
            "se el below"

        OnRight ->
            "se el on-right"

        OnLeft ->
            "se el on-left"

        Overlay ->
            "se el overlay"
