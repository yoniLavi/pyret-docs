#lang scribble/base
@(require "../../scribble-api.rkt" "../abbrevs.rkt")

@(append-gen-docs
  '(module "tables"
    (path "src/js/base/runtime-anf.js")
    (fun-spec
      (name "difference-from"))
    (fun-spec
      (name "running-fold"))
    (fun-spec
      (name "running-reduce"))
    (data-spec
      (name "Table")
      (variants)
      (shared))
    (data-spec
      (name "Reducer")
      (type-vars ("Acc" "InVal" "OutVal"))
      (variants ("reducer"))
      (shared (
        (method-spec (name "reduce"))
        (method-spec (name "one")))))))

@(define (Red-of acc in result) (a-app (a-id "Reducer" (xref "tables" "Reducer")) acc in result))
@(define (red-method name #:args args #:return ret #:contract contract)
  (method-doc "Reducer" "reducer" name #:alt-docstrings "" #:args args #:return ret #:contract contract))
@(define Red-params (list "Acc" "InVal" "OutVal"))

@docmodule["tables" #:noimport #t #:friendly-title "Tables"]{

  Tables consist of a sequence of zero or more @italic{rows}, which each
  contain an equal amount of entries in named @italic{columns}.

  @section[#:tag "s:tables"]{Creating Tables}

Tables are created with a @pyret{table:} expression, which lists any number of
columns, with optional annotations, and then any number of rows.  For example,
this expression creates a table with three columns, @pyret{name}, @pyret{age},
and @pyret{favorite-color}, and three rows:

  @examples{
my-table = table: name :: String, age :: Number, favorite-color :: String
  row: "Bob", 12, "blue"
  row: "Alice", 17, "green"
  row: "Eve", 13, "red"
end
  }

Note that @pyret{my-table} is referred to in many of the following examples.

  @section[#:tag "s:tables:loading"]{Loading Tables}

Table loading expressions allow for the importing of tables from the
outside world into Pyret. Currently, only Google Sheets is supported.
@;(see the @tt{gdrive-sheets} module documentation for details)
In addition to data sources, the notion of @italic{sanitizers} is used. These
are used to properly load each entry of the table as the correct type;
for example, the @pyret{string-sanitizer} in the @tt{data-source} module
causes each item in its column to be loaded as a string (if it is not a
string, it is first converted to one). This is illustrated by the following
example:

@examples{
import data-source as DS
import gdrive-sheets as GS
music-ssheet = GS.load-spreadsheet("<some-spreadsheet-id>")

music = load-table: artist :: String, title :: String, year, sales :: Number
  source: music-ssheet.sheet-by-name("Sales", false)
  sanitize artist using DS.string-sanitizer
  sanitize title using DS.string-sanitizer
  sanitize year using DS.strict-num-sanitizer
  sanitize sales using DS.strict-num-sanitizer
end
}

In general, it is @italic{safest} to sanitize @italic{every} input column, since it
is the only way to guarantee that the data source will not guess the column's
type incorrectly.

Data sources are currently an internal concept to Pyret, so no public
interface for creating them is supported.

While the @tt{data-source} library provides sanitizers which should cover
most use cases, there may be times when one would like to create a custom
data sanitizer. To do so, one must simply create a function which conforms
to the @pyret{Sanitizer<A,B>} type in the @tt{data-source} module.

  @section[#:tag "s:tables:select"]{Selecting Columns}

The @pyret{select} expression can be used to create a new table from a subset
of the columns of an existing one.  For example, we can get just the names
and ages from @pyret{my-table} above:

@pyret-block{
names-and-ages = select name, age from my-table end
check:
  names-and-ages is table: name, age
    row: "Bob", 12
    row: "Alice", 17
    row: "Eve", 13
  end
end
}

  @section{Filtering Tables}

The @pyret{sieve} mechanism allows for filtering out rows of tables based
on some criteria. The @pyret{using} keyword specifies which columns may be
used in the body of the @pyret{sieve} expression.

For instance, we can find the individuals in @pyret{my-table} who are old
enough to drive in the United States.

@pyret-block[#:style "good-ex"]{
can-drive = sieve my-table using age:
  age >= 16
end
check:
  can-drive is table: name, age
    row: "Alice", 17
  end
end
}

Note that the @pyret{sieve} block must explicitly list the columns used to
filter out values with @tt{using}.  The following would signal an undefined
name error for @pyret{age}, because names being used in the expression body
must be listed:

@pyret-block[#:style "bad-ex"]{
can-drive = sieve my-table using name:
  # age is not visible inside of this expression
  age >= 16
end
}

  @section{Ordering Tables}

Since a table consists of a sequence of rows, one may desire to arrange
those rows in some particular order. This can be done with any column whose
type supports the use of @pyret{<} and @pyret{>} by using an @pyret{order}
expression:

@pyret-block{
age-ordered = order my-table:
  age descending
end
check:
  age-ordered is table: name, age
    row: "Alice", 17
    row: "Eve", 13
    row: "Bob", 12
  end
end
}

  @section{Transforming Tables}

The @pyret{transform} expression allows the changing of columns within a
table, similar to the @pyret{map} function over lists (and, just like
@pyret{map}, @pyret{transform} expressions do not mutate the table, but
instead return a new one).

Suppose we find out that @pyret{my-table} is wrong and everyone is actually
a year older than it says they are. We can fix our data as follows:
@pyret-block{
age-fixed = update my-table using age:
  age: age + 1
end
check:
  age-fixed is table: name, age
    row: "Bob", 13
    row: "Alice", 18
    row: "Eve", 14
  end
end
}


@section{Extracting Columns from Tables}

A large number of Pyret modules work on lists instead of tables, so it
may be desired to pull the contents of one column of a table as a list to
use it elsewhere. The @pyret{extract} mechanism allows this ability, and
serves as the primary "link" between processing tabular data and non-tabular
Pyret functions.

Suppose, for example, we wanted just the names of each person in
@pyret{my-table}. We could pull those names out as follows:
@pyret-block{
name-list = extract name from my-table end
check:
  name-list is [list: "Bob", "Alice", "Eve"]
end
}

@section{Extending Tables}

There are two types of extensions which can be made to tables: "mapping" and
"reducing" columns. A "mapping" column is one whose contents depend only on
the row it is being added to. An example of this would be a column which tells
whether the @pyret{age} field of a given row in @pyret{my-table} indicates
that the person in that row can drive in the United States or not (i.e.
whether that person is at least 16):
@pyret-block{
can-drive-col = extend my-table using age:
  can-drive: age >= 16
end
check:
  can-drive-col is table: name, age, can-drive
    row: "Bob", 12, false
    row: "Alice", 17, true
    row: "Eve", 13, false
  end
end
}

Note that just like in @seclink["s:tables:transform"]{@pyret{transform}}, it
is required to specify which columns will be used in the body of the
@pyret{extend} expression using the @pyret{using} keyword.

Conversely, a "reducing" column is one whose information is computed from the
row it is being added to @italic{and the rows above that row}. For example, given
@pyret{can-drive-col} from the previous example, suppose we would like to
keep a running total of how many people are able to drive. Importing the
@tt{tables} module allows us to do this:
@pyret-block{
import tables as TS
num-can-drive-col = extend can-drive-col using can-drive:
  count-true = TS.running-fold(0, {(acc, cur): acc + (if cur: 1 else: 0 end)})
  num-can-drive: count-true of can-drive
end
check:
  num-can-drive-col = table: name, age, can-drive, num-can-drive
    row: "Bob", 12, false, 0
    row: "Alice", 17, true, 1
    row: "Eve", 13, false, 1
  end
end
}

While the reducers found in the @tt{tables} module should cover most all
use cases, there may be times when one would like to create a reducer of their
own. To do so, one must construct an object of the following type:


@type-spec["Reducer" (list "Acc" "InVal" "OutVal")]
@red-method["one"
  #:contract (a-arrow (apply Red-of Red-params) "InVal" (a-tuple "Acc" "OutVal"))
  #:args '(("self" #f) ("value-from-column" #f))
  #:return (a-tuple "Acc" "OutVal")]
@red-method["reduce"
  #:contract (a-arrow (apply Red-of Red-params) "Acc" "InVal" (a-tuple "Acc" "OutVal"))
  #:args '(("self" #f) ("accumulator" #f) ("value-from-column" #f))
  #:return (a-tuple "Acc" "OutVal")]


Reducers are essentially descriptions of folds (in the list @pyret{fold}
sense) over table columns. The way reducers are called by the language
runtime is as follows: the value(s) from the first row are passed to the
reducer's @pyret{.one} method, which should return a tuple containing both
any accumulated information needed for the fold and the value which should
be placed in the new column in that row. The remaining rows are then
sequentially populated using the reducer's @pyret{.reduce} method, which is
identical to the @pyret{.one} method except that it receives an additional
argument which is the previously mentioned accumulated information from the
previous row.

To illustrate, a @pyret{running-mean} reducer which is equivalent to the
one provided by the @tt{tables} module could be implemented as follows:
@pyret-block{
import tables as TS
running-mean :: TS.Reducer<{Number; Number}, Number, Number> = {
  one: lam(n): {{n; 1}; n} end,
  reduce: lam({sum; count}, n):
    { {sum + n; count + 1}; (sum + n) / (count + 1) }
  end
}
}

@subsection{Reducers}

The following reducers are provided:

@value["running-mean" (Red-of N N N)]

@function["difference-from"
  #:contract (a-arrow N (Red-of N N N))
  #:args '(("start-value" #f))
  #:return (Red-of N N N)]{

  }
@function["running-fold"
  #:contract (a-arrow "Result" (a-arrow "Result" "Col" "Result") (Red-of "Result" "Col" "Result"))
  #:args '(("start-value" #f) ("combiner" #f))
  #:return (Red-of "Result" "Col" "Result")]{

@pyret-block{
check:
  count-if-driver = TS.running-fold(0, {(sum, col): if col >= 16: 1 + sum else: sum end})
  t = table: name, age
    row: "Bob", 17
    row: "Mary", 22
    row: "Jane", 6
    row: "Jim", 15
    row: "Barbara", 30
  end
  with-driver-count = extend t using age:
    total-drivers: count-if-driver of age
  end

  with-drive-count is table: name, age, total-drivers
    row: "Bob", 17, 1
    row: "Mary", 22, 2
    row: "Jane", 6, 2
    row: "Jim", 15, 2
    row: "Barbara", 30, 3
  end
end
}

  }

@function["running-reduce"
  #:contract (a-arrow (a-arrow "Col" "Col" "Col") (Red-of "Col" "Col" "Col"))
  #:args '(("combiner" #f))
  #:return (Red-of "Col" "Col" "Col")]{

Creates a reducer that combines the first value in the column with the second,
then the result of that combination with the third, then the result of that
combination with the fourth, and so on.

@pyret-block{
check:
  running-product = TS.running-reduce(lam(x, y): x * y end)

  t = table: outcome, probability
    row: "H-T", 0.5
    row: "T-T", 0.25
    row: "T-T", 0.25
    row: "T-T", 0.25
    row: "H-T", 0.5
    row: "H-T", 0.5
    row: "H-H", 0.25
  end

  with-cumulative = extend t using probability:
    cumulative: running-product of probability
  end

  extract cumulative from with-cumulative end
    is [list: 0.5, 0.125, 0.03125, 0.0078125, 0.00390625, 0.001953125, 0.00048828125]

end
}

  }

@value["difference" (Red-of N N N)]

@value["running-max" (Red-of N N N)]
@value["running-min" (Red-of N N N)]
@value["running-sum" (Red-of N N N)]


  @section[#:tag "s:tables:comparing"]{Comparing Tables}

The order of both rows and columns are part of a table value.  To be considered
equal, tables need to have all the same rows and columns, with the rows and
columns appearing in the same order.



}
