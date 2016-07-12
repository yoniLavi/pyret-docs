#lang scribble/base

@(require
  racket/list
  racket/file
  (only-in racket/string string-join)
  (only-in scribble/core make-style)
  (only-in scribble/html-properties attributes)
  "../../scribble-api.rkt"
  "../../ragged.rkt")

@(define (prod . word)
 (apply tt word))
@(define (file . name)
 (apply tt name))
@(define (in-code . code)
 (apply tt code))
@(define (justcode . stx)
 (nested #:style 'code-inset
  (verbatim (string-join stx ""))))

@(define (prod-tag grammar prod-name) (list 'bnf-prod (list grammar prod-name)))
@(define (prod-ref name) (list "‹" name "›"))
@(define (prod-link grammar name)
   (elemref (prod-tag grammar name) (prod-ref name)))

@(define (render grammar parsed)
   (define-values (constants prods) (partition constant? parsed))
   (define names (map (λ(c) (list (lhs-id-val (constant-lhs c)) (pattern-lit-val (constant-val c)))) constants))
   (define (meta s)
     (elem s #:style (make-style #f (list (attributes '((class . "bnf-meta")))))))
   (define (lit s)
     (elem s #:style (make-style #f (list (attributes '((class . "bnf-lit")))))))
   (define (unknown-lit s)
     (elem s #:style (make-style #f (list (attributes '((class . "bnf-lit bnf-unknown")))))))
     
   (define (render-help p)
     (cond
       [(pattern-seq? p)
        (add-between (map render-help (pattern-seq-vals p)) " ")]
       [(pattern-maybe? p)
        (list (meta "[") (render-help (pattern-maybe-val p)) (meta "]"))]
       [(pattern-repeat? p)
        (list (meta "(") (render-help (pattern-repeat-val p)) (meta ")")
              (if (= 0 (pattern-repeat-min p)) (meta "*") (meta "+")))]
       [(pattern-choice? p)
        (add-between (map render-help (pattern-choice-vals p)) (meta " | "))]
       [(pattern-token? p)
        (define tok (assoc (pattern-token-val p) names))
        (cond
          [tok (lit (second tok))]
          [else (unknown-lit (pattern-token-val p))])]
       [(pattern-lit? p)
        (lit (pattern-lit-val p))]
       [(pattern-id? p)
        (prod-link grammar (pattern-id-val p))]
       [else
        (printf "Unknown prod: ~a" p)]))
   
   (nested #:style (make-style 'code-inset (list (attributes '((style . "white-space: pre;")))))
           (add-between (for/list [(p prods)]
                                  (define rule-name (lhs-id-val (rule-lhs p)))
                                  (list (elemtag (prod-tag grammar rule-name) (prod-ref rule-name)) (meta ":") " " (render-help (rule-pattern p)))
                                  ) "\n")
           )
   )

@(define (bnf grammar . stx)
   (define text (string-join stx ""))
   (define parsed (grammar-parser (tokenize (open-input-string text))))
   (render grammar parsed)
   )

@title[#:tag "s:forms" #:style '(toc)]{Language Constructs}

This section contains information on the various language forms in Pyret, from
binary operators to data definitions to functions.  This is a more detailed
reference to the grammar of expressions and statements and their evaluation,
rather than to

@(table-of-contents)

@section[#:tag "s:program"]{Programs}

Programs consist of a sequence of import or provide statements, followed by a
block:

@bnf['Pyret]{
PROVIDE: "provide"
STAR: "*"
PROVIDE-TYPES: "provide-types"
program: prelude block
prelude: [provide-stmt] [provide-types-stmt] import-stmt*

provide-stmt: PROVIDE stmt end | PROVIDE STAR
provide-types-stmt: PROVIDE-TYPES record-ann | PROVIDE-TYPES STAR
}

@section{Import Statements}

Import statements come in a few forms:

@bnf['Pyret]{
IMPORT: "import"
AS: "as"
PARENNOSPACE: "("
COMMA: ","
RPAREN: ")"
FROM: "from"
import-stmt: IMPORT import-source AS NAME
import-stmt: IMPORT NAME (COMMA NAME)* FROM import-source
import-source: import-special | import-name | import-string
import-special: NAME PARENNOSPACE STRING (COMMA STRING)* RPAREN
import-name: NAME
import-string: STRING
}

The form with @prod-link['Pyret]{import-name} looks for a file with that name in the
built-in libraries of Pyret, and it is an error if there is no such library.

Example:

@pyret{
  import equality as EQ
  check:
    f = lam(): "" end
    EQ.equal-always3(f, f) is EQ.Unknown
  end
}

@section{Provide Statements}

A provide statement comes in one of two forms:

@bnf['Pyret]{
PROVIDE: "provide"
END: "end"
STAR: "*"
provide-stmt: PROVIDE stmt END | PROVIDE STAR
}

Both forms have no effect when the program is run as the top-level program.

When the program is in a file that is evaluated via @tt{import}, the program is
run, and then the @tt{provide} statement is run in top-level scope to determine
the value bound to the identifier in the import statement.

In the first form, the @tt{stmt} internal to the provide is evaluated, and the
resulting value is provided.

The second form is syntactic sugar for:

@pyret-block{
provide {
  id: id,
  ...
} end
}

Where the @justcode{id}s are all the toplevel names in the file defined with
@pyret{fun}, @pyret{data}, or @pyret{x = e}.

@section{Blocks}

A block's syntax is a list of statements:

@bnf['Pyret]{
block: stmt*
}

Blocks serve two roles in Pyret:

@itemlist[
  @item{Sequencing of operations}
  @item{Units of lexical scope}
]

The @prod-link['Pyret]{let-expr}, @tt{fun-expr}, @tt{data-expr}, and @tt{var-expr} forms are
handled specially and non-locally within blocks.  A detailed description of
scope will appear here soon.

Blocks evaluate each of their statements in order, and evaluate to the value of
the final statement in the block.

@section{Statements}

There are a number of forms that can only appear as statements in @tt{block}s
and @tt{provide} expressions:

@bnf['Pyret]{
stmt: let-expr | fun-expr | data-expr | when-expr
    | var-expr | assign-expr | binop-expr
}

@subsection[#:tag "s:let-expr"]{Let Expressions}

Let expressions are written with an equals sign:

@bnf['Pyret]{
EQUALS: "="
let-expr: binding EQUALS binop-expr
}

A let statement causes the name in the @tt{binding} to be put in scope in the
current block, and upon evaluation sets the value to be the result of
evaluating the @tt{binop-expr}.  The resulting binding cannot be changed via an
@tt{assign-expr}, and cannot be shadowed by other bindings within the same or
nested scopes:

@pyret-block{
x = 5
x := 10
# Error: x is not assignable

}

@pyret-block{
x = 5
x = 10
# Error: x defined twice

}

@pyret-block{
x = 5
fun f():
  x = 10
  x
end
# Error: can't use the name x in two nested scopes

}

@pyret-block{
fun f():
  x = 10
  x
end
fun g():
  x = 22
  x
end
# Not an error: x is used in two scopes that are not nested
}

@subsection[#:tag "s:fun-expr"]{Function Declaration Expressions}

Function declarations have a number of pieces:

@bnf['Pyret]{
FUN: "fun"
COLON: ":"
END: "end"
LANGLE: "<"
RANGLE: ">"
COMMA: ","
LPAREN: "("
THINARROW: "->"
DOC: "doc:"
WHERE: "where:"
fun-expr: FUN NAME fun-header COLON doc-string block where-clause END
fun-header: ty-params args return-ann
ty-params:
  [LANGLE list-ty-param* NAME RANGLE]
list-ty-param: NAME COMMA
args: LPAREN [list-arg-elt* binding] RPAREN
list-arg-elt: binding COMMA
return-ann: [THINARROW ann]
doc-string: [DOC STRING]
where-clause: [WHERE block]
}

A function expression is syntactic sugar for a let and an anonymous function
expression for non-recursive case. The statement:

@justcode{
"fun" NAME ty-params args return-ann ":"
  doc-string
  block
  where-clause
"end"
}

is equivalent to

@justcode{
NAME "=" "lam" ty-params args return-ann ":"
  doc-string
  block
"end"
}

With the @tt{where-clause} registered in check mode.  Concretely:

@pyret-block{
fun f(x, y):
  x + y
end
}

is equivalent to

@pyret-block{
f = lam(x, y):
  x + y
end
}

See the documentation for @tt{lambda-exprs} for an explanation of arguments'
and annotations' behavior, as well as @tt{doc-strings}.

@subsection[#:tag "s:data-expr"]{Data Declarations}

Data declarations define a number of related functions for creating and
manipulating a data type.  Their grammar is:

@bnf['Pyret]{
COLON: ":"
END: "end"
DATA: "data"
PIPE: "|"
LPAREN: "("
RPAREN: ")"
data-expr: DATA NAME ty-params data-mixins COLON
    data-variant*
    data-sharing
    where-clause
  END
data-variant: PIPE NAME variant-members data-with | PIPE NAME data-with
variant-members: LPAREN [list-variant-member* variant-member] RPAREN
COMMA: ","
REF: "ref"
list-variant-member: variant-member COMMA
variant-member: [REF] binding
WITH: "with:"
data-with: [WITH fields]
SHARING: "sharing:"
data-sharing: [SHARING fields]
}

@; data-mixins: ["deriving" mixins] ;; we don't have mixins yet

A @tt{data-expr} causes a number of new names to be bound in the scope of the
block it is defined in:

@itemlist[
  @item{The @tt{NAME} of the data definition}
  @item{@tt{NAME}, for each variant of the data definition}
  @item{@tt{is-NAME}, for each variant of the data definition}
]

For example, in this data definition:

@pyret-block{
data BTree:
  | node(value :: Number, left :: BTree, right :: BTree)
  | leaf(value :: Number)
end
}

These names are defined, with the given types:

@pyret-block{
BTree :: (Any -> Bool)
node :: (Number, BTree, BTree -> BTree)
is-node :: (Any -> Bool)
leaf :: (Number -> BTree)
is-leaf :: (Any -> Bool)
}

We call @tt{node} and @tt{leaf} the @emph{constructors} of @tt{BTree}, and they
construct values with the named fields.  They will refuse to create the value
if fields that don't match the annotations are given.  As with all annotations,
they are optional.  The constructed values can have their fields accessed with
@seclink["s:dot-expr" "dot expressions"].

The function @tt{BTree} is a @emph{detector} for values created from this data
definition, and can be used as an annotation to check for values created by the
constructors of @tt{BTree}.  @tt{BTree} returns true when provided values
created by @tt{node} or @tt{leaf}, but no others.

The functions @tt{is-node} and @tt{is-leaf} are detectors for the values
created by the individual constructors: @tt{is-node} will only return @tt{true}
for values created by calling @tt{node}, and correspondingly for @tt{leaf}.

Here is a longer example of the behavior of detectors, field access, and
constructors:

@pyret-block{
data BTree:
  | node(value :: Number, left :: BTree, right :: BTree)
  | leaf(value :: Number)
where:
  a-btree = node(1, leaf(2), node(3, leaf(4), leaf(5)))

  BTree(a-btree) is true
  BTree("not-a-tree") is false
  BTree(leaf(5)) is true
  is-leaf(leaf(5)) is true
  is-leaf(a-btree) is false
  is-leaf("not-a-tree") is false
  is-node(leaf(5)) is false
  is-node(a-btree) is true
  is-node("not-a-tree") is false

  a-btree.value is 1
  a-btree.left.value is 2
  a-btree.right.value is 3
  a-btree.right.left.value is 4
  a-btree.right.right.value is 4

end
}

A data definition can also define, for each instance as well as for the data
definition as a whole, a set of methods.  This is done with the keywords
@tt{with:} and @tt{sharing:}.  Methods defined on a variant via @tt{with:} will
only be defined for instances of that variant, while methods defined on the
union of all the variants with @tt{sharing:} are defined on all instances.  For
example:

@pyret-block{
data BTree:
  | node(value :: Number, left :: BTree, right :: BTree) with:
    method size(self): 1 + self.left.size() + self.right.size() end
  | leaf(value :: Number) with:
    method size(self): 1 end,
    method increment(self): leaf(self.value + 1) end
sharing:
  method values-equal(self, other):
    self.value == other.value
  end
where:
  a-btree = node(1, leaf(2), node(3, leaf(4), leaf(2)))
  a-btree.values-equal(leaf(1)) is true
  leaf(1).values-equal(a-btree) is true
  a-btree.size() is 3
  leaf(0).size() is 1
  leaf(1).increment() is leaf(2)
  a-btree.increment() # raises error: field increment not found.
end
}

@subsection[#:tag "s:when-exp"]{When Expressions}

A when expression has a single test condition with a corresponding
block.

@bnf['Pyret]{
WHEN: "when"
COLON: ":"
END: "end"
when-expr: WHEN binop-expr COLON block END
}

For example:

@pyret-block{
when x == 42:
  print("answer")
end
}

If the test condition is true, the block is evaluated. If the
test condition is false, nothing is done, and @pyret{nothing} is returned.

@subsection[#:tag "s:var-expr"]{Variable Declarations}

Variable declarations look like @seclink["s:let-expr" "let bindings"], but
with an extra @tt{var} keyword in the beginning:

@bnf['Pyret]{
             VAR: "var"
             EQUALS: "="
var-expr: VAR binding EQUALS expr
}

A @tt{var} expression creates a new @emph{assignable variable} in the current
scope, initialized to the value of the expression on the right of the @tt{=}.
It can be accessed simply by using the variable name, which will always
evaluate to the last-assigned value of the variable.  @seclink["s:assign-expr"
"Assignment statements"] can be used to update the value stored in an
assignable variable.

If the @tt{binding} contains an annotation, the initial value is checked
against the annotation, and all @seclink["s:assign-expr" "assignment
statements"] to the variable check the annotation on the new value before
updating.

@subsection[#:tag "s:assign-expr"]{Assignment Statements}

Assignment statements have a name on the left, and an expression on the right
of @tt{:=}:

@bnf['Pyret]{
             COLON-EQUALS: ":="
assign-expr: NAME COLON-EQUALS binop-expr
}

If @tt{NAME} is not declared in the same or an outer scope of the assignment
expression with a @tt{var} declaration, the program fails with a static error.

At runtime, an assignment expression changes the value of the assignable
variable @tt{NAME} to the result of the right-hand side expression.

@section{Expressions}

@subsection[#:tag "s:lam-expr"]{Lambda Expressions}

The grammar for a lambda expression is:

@bnf['Pyret]{
             LAM: "lam"
             COLON: ":"
             END: "end"
lambda-expr: LAM fun-header COLON
    doc-string
    block
    where-clause
  END
LANGLE: "<"
RANGLE: ">"
ty-params:
  [LANGLE list-ty-param* NAME RANGLE]
list-ty-param: NAME COMMA
COMMA: ","
LAPREN: "("
RPAREN: ")"
args: LPAREN [list-arg-elt* binding] RPAREN
list-arg-elt: binding COMMA
THINARROW: "->"
DOC: "doc:"
return-ann: [THINARROW ann]
doc-string: [DOC STRING]
}

A lambda expression creates a function value that can be applied with
@seclink["s:app-expr" "application expressions"].  The arguments in @tt{args}
are bound to their arguments as immutable identifiers as in a
@seclink["s:let-expr" "let expression"].

@examples{
check:
  f = lam(x, y): x - y end
  f(5, 3) is 2
end
}

These identifiers follow the same rules of no shadowing and no assignment.

@examples{
x = 12
f = lam(x): x end  # ERROR: x shadows a previous definition
g = lam(y):
  y := 10   # ERROR: y is not a variable and cannot be assigned
  y + 1
end
}

If the arguments have @seclink["s:annotations" "annotations"] associated with
them, they are checked before the body of the function starts evaluating, in
order from left to right.  If an annotation fails, an exception is thrown.

@pyret-block{
add1 = lam(x :: Number):
  x + 1
end
add1("not-a-number")
# Error: expected a Number and got "not-a-number"
}

A lambda expression can have a @emph{return} annotation as well, which is
checked before evaluating to the final value:


@examples{
add1 = lam(x) -> Number:
  tostring(x) + "1"
end
add1(5)
# Error: expected a Number and got "51"
}

Lambda expressions remember, or close over, the values of other identifiers
that are in scope when they are defined.  So, for example:

@examples{
check:
  x = 10
  f = lam(y): y + x end
  f(5) is 15
end
}

@subsection[#:tag "s:curly-lam-expr"]{Curly-Brace Lambda Shorthand}

Lambda expressions can also be written with a curly-brace shorthand:

@justcode{
curly-lambda-expr: "{" ty-params [args] return-ann ":"
    doc-string
    block
  "}"
}

@examples{
check:
  x = 10
  f = {(y :: Number) -> Number: x + y}
  f(5) is 15
end
}


@subsection[#:tag "s:app-expr"]{Application Expressions}

Function application expressions have the following grammar:

@bnf['Pyret]{
             LPAREN: "("
             RPAREN: ")"
             COMMA: ","
app-expr: expr app-args
app-args: LPAREN [app-arg-elt* binop-expr] RPAREN
app-arg-elt: binop-expr COMMA
}

An application expression is an expression followed by a comma-separated list
of arguments enclosed in parentheses.  It first evaluates the arguments in
left-to-right order, then evaluates the function position.  If the function
position is a function value, the number of provided arguments is checked
against the number of arguments that the function expects.  If they match, the
arguments names are bound to the provided values.  If they don't, an exception
is thrown.

Note that there is @emph{no space} allowed before the opening parenthesis of
the application.  If you make a mistake, Pyret will complain:

@pyret-block{
f(1) # This is the function application expression f(1)
f (1) # This is the id-expr f, followed by the paren-expr (1)
# The second form yields a well-formedness error that there
# are two expressions on the same line
}

@subsection[#:tag "s:curried-apply-expr"]{Curried Application Expressions}

Suppose a function is defined with multiple arguments:

@pyret-block{
fun f(v, w, x, y, z): ... end
}

Sometimes, it is particularly convenient to define a new function that
calls @tt{f} with some arguments pre-specified:

@pyret-block{
call-f-with-123 = lam(y, z): f(1, 2, 3, y, z) end
}

Pyret provides syntactic sugar to make writing such helper functions
easier:

@pyret-block{
call-f-with-123 = f(1, 2, 3, _, _) # same as the fun expression above
}

Specifically, when Pyret code contains a function application some of
whose arguments are underscores, it constructs an lambda expression
with the same number of arguments as there were underscores in the
original expression, whose body is simply the original function
application, with the underscores replaced by the names of the
arguments to the anonymous function.

This syntactic sugar also works
with operators.  For example, the following are two ways to sum a list
of numbers:

@pyret-block{
[list: 1, 2, 3, 4].foldl(lam(a, b): a + b end, 0)

[list: 1, 2, 3, 4].foldl(_ + _, 0)
}

Likewise, the following are two ways to compare two lists for
equality:

@pyret-block{
list.map_2(lam(x, y): x == y end, first-list, second-list)

list.map_2(_ == _, first-list, second-list)
}

Note that there are some limitations to this syntactic sugar.  You
cannot use it with the @tt{is} or @tt{raises} expressions in
check blocks, since both test expressions and expected
outcomes are known when writing tests.  Also, note that the sugar is
applied only to one function application at a time.  As a result, the
following code:

@pyret-block{
_ + _ + _
}

desugars to

@pyret-block{
lam(z):
  (lam(x, y): x + y end) + z
end
}

which is probably not what was intended.  You can still write the
intended expression manually:

@pyret-block{
lam(x, y, z): x + y + z end
}

Pyret just does not provide syntactic sugar to help in this case
(or other more complicated ones).

@subsection[#:tag "s:cannonball-expr"]{Chaining Application}

@bnf['Pyret]{
CARET: "^"
chain-app-expr: binop-expr CARET binop-expr
}

The expression @pyret{e1 ^ e2} is equivalent to @pyret{e2(e1)}.  It's just
another way of writing a function application to a single argument.

Sometimes, composing functions doesn't produce readable code.  For example, if
say we have a @pyret{Tree} datatype, and we have an @pyret{add} operation on
it, defined via a function.  To build up a tree with a series of adds, we'd
write something like:

@pyret-block{
t = add(add(add(add(empty-tree, 1), 2), 3), 4)
}

Or maybe

@pyret-block{
t1 = add(empty-tree, 1)
t2 = add(t1, 2)
t3 = add(t2, 3)
t  = add(t3, 4)
}

If @pyret{add} were a method, we could write:

@pyret-block{
t = empty-tree.add(1).add(2).add(3).add(4)
}

which would be more readable, but since @pyret{add} is a function, this doesn't
work.

In this case, we can write instead:

@pyret-block{
t = empty-tree ^ add(_, 1) ^ add(_, 2) ^ add(_, 3)
}

This uses @seclink["s:curried-apply-expr" "curried application"] to create a
single argument function, and chaining application to apply it.  This can be
more readable across several lines of initialization as well, when compared to
composing “inside-out” or using several intermediate names:

@pyret-block{
t = empty-tree
  ^ add(_, 1)
  ^ add(_, 2)
  ^ add(_, 3)
  # and so on
}

@subsection[#:tag "s:binop-expr"]{Binary Operators}

There are a number of binary operators in Pyret.  A binary operator expression
is a series of expressions joined by binary operators. An expression itself
is also a binary operator expression.

@bnf['Pyret]{
binop-expr: expr (BINOP expr)*
}

Each binary operator is syntactic sugar for a particular method or function
call.  The following table lists the operators, their intended use, and the
corresponding call:

@tabular[#:sep @hspace[2]
  (list
    (list @tt{left + right} @tt{left._plus(right)})
    (list @tt{left - right} @tt{left._minus(right)})
    (list @tt{left * right} @tt{left._times(right)})
    (list @tt{left / right} @tt{left._divide(right)})
    (list @tt{left <= right} @tt{left._lessequal(right)})
    (list @tt{left < right} @tt{left._lessthan(right)})
    (list @tt{left >= right} @tt{left._greaterequal(right)})
    (list @tt{left > right} @tt{left._greaterthan(right)}))
]

For the primitive strings and numbers, the operation happens internally.  For
all object values, the operator looks for the method appropriate method and
calls it.  The special names allow a form of operator overloading, and avoid
adding an extra concept beyond function and method calls to the core to
account for these binary operations.

@subsection[#:tag "s:obj-expr"]{Object Expressions}

Object expressions map field names to values:

@bnf['Pyret]{
             LBRACE: "{"
             RBRACE: "}"
obj-expr: LBRACE fields RBRACE | LBRACE RBRACE
COMMA: ","
COLON: ":"
fields: list-field* field [COMMA]
list-field: field COMMA
END: "end"
METHOD: "method"
field: key COLON binop-expr
     | METHOD key fun-header COLON doc-string block where-clause END
key: NAME
}

A comma-separated sequence of fields enclosed in @tt{{}} creates an object; we
refer to the expression as an @emph{object literal}.  There are two types of
fields: @emph{data} fields and @emph{method} fields.  A data field in an object
literal simply creates a field with that name on the resulting object, with its
value equal to the right-hand side of the field. A method field

@justcode{
"method" key fun-header ":" doc-string block where-clause "end"
}

is syntactic sugar for:

@justcode{
key ":" "method" fun-header ":" doc-string block where-clause "end"
}

That is, it's just special syntax for a data field that contains a method
value.

The fields are evaluated in the order they appear.  If the same field appears
more than once, it is a compile-time error.

@subsection[#:tag "s:dot-expr"]{Dot Expressions}

A dot expression is any expression, followed by a dot and name:

@bnf['Pyret]{
             DOT: "."
dot-expr: expr DOT NAME
}

A dot expression evaluates the @tt{expr} to a value @tt{val}, and then does one
of three things:

@itemlist[
  @item{Raises an exception, if @tt{NAME} is not a field of @tt{expr}}

  @item{Evaluates to the value stored in @tt{NAME}, if @tt{NAME} is present and
  not a method}

  @item{

    If the @tt{NAME} field is a method value, evaluates to a function that is
    the @emph{method binding} of the method value to @tt{val}.  For a method

    @pyret-block{
      m = method(self, x): body end
    }

    The @emph{method binding} of @tt{m} to a value @tt{v} is equivalent to:

    @pyret-block{
      (lam(self): lam(x): body end end)(v)
    }

    What this detail means is that you can look up a method and it
    automatically closes over the value on the left-hand side of the dot.  This
    bound method can be freely used as a function.

    For example:

    @pyret-block{
      o = { method m(self, x): self.y + x end, y: 22 }
      check:
        the-m-method-closed-over-o = o.m
        the-m-method-closed-over-o(5) is 27
      end
    }
  }
]

@subsection[#:tag "s:extend-expr"]{Extend Expressions}

The extend expression consists of an base expression and a list of fields to
extend it with:

@bnf['Pyret]{
             DOT: "."
             LBRACE: "{"
             RBRACE: "}"
extend-expr: expr DOT LBRACE fields RBRACE
}

The extend expression first evaluates @tt{expr} to a value @tt{val}, and then
creates a new object with all the fields of @tt{val} and @tt{fields}.  If a
field is present in both, the new field is used.

Examples:

@pyret-block{
check:
  o = {x : "original-x", y: "original-y"}
  o2 = o.{x : "new-x", z : "new-z"}
  o2.x is "new-x"
  o2.y is "original-y"
  o2.z is "new-z"
end
}

@subsection[#:tag "s:if-expr"]{If Expressions}

An if expression has a number of test conditions and an optional else case.

@bnf['Pyret]{
             IF: "if"
             COLON: ":"
             ELSECOLON: "else:"
             ELSEIF: "else if"
             END: "end"
if-expr: IF binop-expr COLON block else-if* [ELSECOLON block] END
else-if: ELSEIF binop-expr COLON block
}

For example, this if expression has an "else:"

@pyret-block{
if x == 0:
  1
else if x > 0:
  x
else:
  x * -1
end
}

This one does not:

@pyret-block{
if x == 0:
  1
else if x > 0:
  x
end
}

Both are valid.  The conditions are tried in order, and the block corresponding
to the first one to return @pyret{true} is evaluated.  If no condition matches,
the else branch is evaluated if present.  If no condition matches and no else
branch is present, an error is thrown.  If a condition evaluates to a value
other than @pyret{true} or @pyret{false}, a runtime error is thrown.

@subsection[#:tag "s:ask-expr"]{Ask Expressions}

An @pyret{ask} expression is a different way of writing an @pyret{if}
expression that can be easier to read in some cases.

@bnf['Pyret]{
             ASKCOLON: "ask:"
             BAR: "|"
             OTHERWISECOLON: "otherwise:"
             THENCOLON: "then:"
             END: "end"
ask-expr: ASKCOLON ask-branch* [BAR OTHERWISECOLON block] END
ask-branch: BAR binop-expr THENCOLON block
}

This ask expression:

@pyret-block{
ask:
  | x == 0 then: 1
  | x > 0 then: x
  | otherwise: x * -1
end
}

is equivalent to

@pyret-block{
if x == 0:
  1
else if x > 0:
  x
else:
  x * -1
end
}

Similar to @pyret{if}, if an @pyret{otherwise:} branch isn't specified and no
branch matches, a runtime error results.

@subsection[#:tag "s:cases-expr"]{Cases Expressions}

A cases expression consists of a datatype (in parentheses), an expression to
inspect (before the colon), and a number of branches.  It is intended to be
used in a structure parallel to a data definition.

@bnf['Pyret]{
             CASES: "cases"
             LPAREN: "("
             RPAREN: ")"
             COLON: ":"
             BAR: "|"
             ELSE: "else"
             THICKARROW: "=>"
             END: "end"
cases-expr: CASES LPAREN check-ann RPAREN expr COLON
    cases-branch*
    [BAR ELSE THICKARROW block]
  END
cases-branch: BAR NAME [args] THICKARROW block
}

The @pyret{check-ann} must be a type, like @pyret-id["List" "lists"].  Then
@pyret{expr} is evaluated and checked against the given annotation.  If
it has the right type, the cases are then checked.

Cases should use the names of the variants of the given data type as the
@tt{NAME}s of each branch.  In the branch that matches, the fields of the
variant are bound, in order, to the provided @tt{args}, and the right-hand side
of the @tt{=>} is evaluated in that extended environment.  An exception results
if the wrong number of arguments are given.

An optional @tt{else} clause can be provided, which is evaluated if no cases
match.  If no @tt{else} clause is provided, a runtime error results.

For example, some cases expression on lists looks like:

@pyret-block{
check:
  result = cases(List) [list: 1,2,3]:
    | empty => "empty"
    | link(f, r) => "link"
  end
  result is "link"

  result2 = cases(List) [list: 1,2,3]:
    | empty => "empty"
    | else => "else"
  end
  result2 is else

  result3 = cases(List) empty:
    | empty => "empty"
    | else => "else"
  end
  result3 is "empty"
end
}

@subsection[#:tag "s:for-expr"]{For Expressions}

For expressions consist of the @tt{for} keyword, followed by a list of
@tt{binding from expr} clauses in parentheses, followed by a block:

@bnf['Pyret]{
             FOR: "for"
             PARENNOSPACE: "("
             RPAREN: ")"
             COLON: ":"
             END: "end"
for-expr: FOR expr PARENNOSPACE [for-bind-elt* for-bind] RPAREN return-ann COLON
  block
END
COMMA: ","
for-bind-elt: for-bind COMMA
FROM: "from"
for-bind: binding FROM binop-expr
}

The for expression is just syntactic sugar for a
@seclink["s:lam-expr"]{@tt{lam-expr}} and a @seclink["s:app-expr"]{@tt{app-expr}}.  An expression

@pyret-block{
for fun-expr(arg1 :: ann1 from expr1, ...) -> ann-return:
  block
end
}

is equivalent to:

@pyret-block{
fun-expr(lam(arg1 :: ann1, ...) -> ann-return: block end, expr1, ...)
}

Using a @tt{for-expr} can be a more natural way to call, for example, list
iteration functions because it puts the identifier of the function and the
value it draws from closer to one another.  Use of @tt{for-expr} is a matter of
style; here is an example that compares @tt{fold} with and without @tt{for}:

@pyret-block{
for fold(sum from 0, number from [list: 1,2,3,4]):
  sum + number
end

fold(lam(sum, number): sum + number end, 0, [list: 1,2,3,4])
}

@subsection[#:tag "s:template-expr"]{Template (...) Expressions}

A template expression is three dots in a row:

@justcode{
template-expr: "..."
}

It is useful for a placeholder for other expressions in code-in-progress.  When
it is evaluated, it raises a runtime exception that indicates the expression it
is standing in for isn't yet implemented:

@examples{
fun list-sum(l :: List<Number>) -> Number:
  cases(List<Number>) l:
    | empty => 0
    | link(first, rest) => first + ...
  end
end
check:
  list-sum(empty) is 0
  list-sum(link(1, empty)) raises "template-not-finished"
end
}

This is handy for starting a function (especially one with many cases) with
some tests written and others to be completed.

@margin-note{These other positions for @tt{...} may be included in the future.}
The @tt{...} expression can only appear where @emph{expressions} can appear.
So it is not allowed in binding positions or annotation positions.  These are
not allowed:

@examples{
fun f(...): # parse error
  "todo"
end
x :: ... = 5 # parse error
}


@section[#:tag "s:annotations"]{Annotations}

Annotations in Pyret express intended types values will have at runtime.
They appear next to identifiers anywhere a @tt{binding} is specified in the
grammar, and if an annotation is present adjacent to an identifier, the program
is compiled to raise an error if the value bound to that identifier would
behave in a way that violates the annotation.  The annotation provides a
@emph{guarantee} that either the value will behave in a particular way, or the
program will raise an exception. In addition, annotations can be checked
by Pyret's @seclink["type-check"]{type checker} to ensure that all values
have the expected types and are used correctly.

@subsection[#:tag "s:name-ann"]{Name Annotations}

Some annotations are simply names.  For example, a
@seclink["s:data-expr"]{@tt{data declaration}} binds the name of the
declaration as a value suitable for use as a name annotation.  There are
built-in name annotations, too:

@justcode{
Any
Number
String
Boolean
}

Each of these names represents a particular type of runtime value, and using
them in annotation position will check each time the identifier is bound that
the value is of the right type.

@pyret-block{
x :: Number = "not-a-number"
# Error: expected Number and got "not-a-number"
}

@tt{Any} is an annotation that allows any value to be used.  It's semantically
equivalent to not putting an annotation on an identifier, but it allows a
program to clearly signal that no restrictions are intended for the identifier
it annotates.

@subsection[#:tag "s:arrow-ann"]{Arrow Annotations}

An arrow annotation is used to describe the behavior of functions.  It consists
of a list of comma-separated argument types followed by an ASCII arrow and
return type:

@bnf['Pyret]{
             LPAREN: "("
             RPAREN: ")"
             THINARROW: "->"
             COMMA: ","
arrow-ann: LPAREN arrow-ann-elt* ann THINARROW ann RPAREN
arrow-ann-elt: ann COMMA
}

When an arrow annotation appears in a binding, that binding position simply
checks that the value is a function.

