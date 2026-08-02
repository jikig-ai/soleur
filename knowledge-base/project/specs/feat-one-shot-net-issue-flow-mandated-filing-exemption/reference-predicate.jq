def strip_fences:
  (. // "") | split("\n")
  | reduce .[] as $l ({inf:false, out:[]};
      if ($l | test("^[ \t]*```")) then .inf = (.inf | not)
      elif .inf then .
      else .out += [$l] end)
  | .out | join("\n");

def claims($ok):
  strip_fences | split("\n")
  | map(select(test("^[ \t\r]*[Mm]andated-[Bb]y:[ \t\r]*[A-Za-z0-9-]+[ \t\r]*$")))
  | map(capture("[Mm]andated-[Bb]y:[ \t\r]*(?<id>[A-Za-z0-9-]+)").id | ascii_downcase);

[ .issues[]
  | . as $i
  | ($i.body | claims($ok)) as $c
  | { n: $i.number,
      exempt: (
        ($c | length) == 1
        and ($ok | index($c[0])) != null
        and ($i.state == "OPEN")
        and ($prbody | strip_fences
             | test("(Tracks|Refs)[ \t]+#" + ($i.number|tostring) + "([^0-9]|$)"))
      ),
      claim: (if ($c|length)==1 then $c[0] else "<none-or-multi>" end) } ]
