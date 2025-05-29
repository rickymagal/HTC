{-# LANGUAGE LambdaCase, OverloadedStrings #-}

-- | ASTGen provides a function to render the program’s Abstract Syntax Tree
--   as a Graphviz DOT graph.
module ASTGen
  ( programToDot
  ) where

import Data.Text.Lazy (Text)
import qualified Data.Text.Lazy as T
import Syntax (Program(..), Decl(..), Expr(..), Pattern(..))

-- | Convert an entire 'Program' AST into a DOT-formatted graph.
--
-- Each top-level function declaration is numbered sequentially and rendered
-- as a subgraph.  The output is a valid Graphviz DOT description of the AST.
programToDot :: Program -> Text
programToDot (Program decls) =
     "digraph AST {\n"
  <> "  node [shape=box, fontname=\"Courier\"];\n"
  <> T.concat (zipWith (\i d -> declToDot ("decl" <> T.pack (show i)) d) [0..] decls)
  <> "}\n"

-- | Render a single function declaration as a DOT subgraph.
--
-- The root node is labeled "FunDecl\n<name>(<params>)", and connected
-- to its body node, which recursively expands the expression tree.
declToDot :: Text -> Decl -> Text
declToDot name (FunDecl f ps b) =
    let lbl   = "FunDecl\n" <> T.pack f
             <> "(" <> T.intercalate "," (map T.pack ps) <> ")"
        bodyN = name <> "_body"
    in  node name lbl
     <> node bodyN (exprLabel b)
     <> edge name bodyN
     <> exprToDot bodyN b

-- | Generate a human-readable label for an expression node.
--
-- For example, a variable becomes "Var\nx", a lambda becomes "Lambda(x,y)"
-- showing its parameters, and binary operators are annotated with their name.
exprLabel :: Expr -> Text
exprLabel = \case
  Var x        -> "Var\n" <> T.pack x
  Lit _        -> "Lit"
  Lambda ps _  -> "Lambda(" <> T.intercalate "," (map T.pack ps) <> ")"
  If{}         -> "If"
  Case{}       -> "Case"
  Let{}        -> "Let"
  App{}        -> "App"
  BinOp op _ _ -> "BinOp\n" <> T.pack (show op)
  UnOp op _    -> "UnOp\n" <> T.pack (show op)
  List{}       -> "List"
  Tuple{}      -> "Tuple"

-- | Recursively render the children of an expression node.
--
-- Each child is given a name based on the parent prefix plus role,
-- connected by an edge, and then its subtree is expanded.
exprToDot :: Text -> Expr -> Text
exprToDot prefix expr = case expr of
  Var{}    -> ""
  Lit{}    -> ""
  Lambda _ b ->
      child prefix "body" b

  If c t e ->
      children prefix ["cond","then","else"] [c,t,e]

  Case s alts ->
      child prefix "scrut" s
    <> T.concat [ altToDot prefix i pat bd
                | (i,(pat,bd)) <- zip [0..] alts ]

  Let ds e ->
      T.concat [ declToDot (prefix <> "_let" <> T.pack (show i)) d
               | (i,d) <- zip [0..] ds ]
    <> child prefix "in" e

  App f x ->
      children prefix ["fun","arg"] [f,x]

  BinOp _ l r ->
      children prefix ["l","r"] [l,r]

  UnOp _ x ->
      child prefix "arg" x

  List xs ->
      T.concat [ child prefix (T.pack $ "e" ++ show i) x
               | (i,x) <- zip [0..] xs ]

  Tuple xs ->
      T.concat [ child prefix (T.pack $ "e" ++ show i) x
               | (i,x) <- zip [0..] xs ]

  where
    -- | Render a single child node and connect it.
    child p role e =
      let n = p <> "_" <> role
      in  node n (exprLabel e)
       <> edge p n
       <> exprToDot n e

    -- | Render multiple children with given roles.
    children p rs es = T.concat $ zipWith (\r e -> child p r e) rs es

-- | Render a case alternative (pattern and corresponding body) as DOT.
altToDot :: Text -> Int -> Pattern -> Expr -> Text
altToDot prefix i pat bd =
  let pn = prefix <> "_pat" <> T.pack (show i)
      bn = prefix <> "_bd"  <> T.pack (show i)
  in  node pn (patternLabel pat)
   <> edge prefix pn
   <> node bn "AltBody"
   <> edge pn bn
   <> exprToDot bn bd

-- | Generate a label for a pattern node.
patternLabel :: Pattern -> Text
patternLabel = \case
  PWildcard   -> "_"
  PVar x      -> T.pack x
  PLit _      -> "LitPat"
  PList _     -> "ListPat"
  PTuple _    -> "TuplePat"

-- | Define a DOT node with the given name and label.
node :: Text -> Text -> Text
node name label =
  "  " <> name <> " [label=\"" <> label <> "\"];\n"

-- | Define a DOT edge between two nodes.
edge :: Text -> Text -> Text
edge from to =
  "  " <> from <> " -> " <> to <> ";\n"
