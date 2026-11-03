#!/usr/bin/env bash
# Usage: languages-card.sh <github-login> <out.svg>
# Needs GH_TOKEN. Weights each repo equally (its language shares, not raw bytes, so huge repos do not drown the rest) over every non-fork repo the user owns, collaborates on or reaches through an org.
set -euo pipefail

login="$1"
out="$2"

gh api graphql --paginate -F login="$login" -f query='
  query($login: String!, $endCursor: String) {
    user(login: $login) {
      repositories(first: 100, after: $endCursor, ownerAffiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER], isFork: false) {
        pageInfo { hasNextPage endCursor }
        nodes {
          languages(first: 10, orderBy: {field: SIZE, direction: DESC}) {
            totalSize
            edges { size node { name color } }
          }
        }
      }
    }
  }' | jq -rs '
  def esc: gsub("&"; "&amp;") | gsub("<"; "&lt;");
  def pct($n; $t): (($n * 1000 / $t | round) / 10 | tostring) + "%";

  [.[].data.user.repositories.nodes[].languages | select(.totalSize > 0) | .totalSize as $t | .edges[] | .size = (.size / $t)]
  | group_by(.node.name)
  | map({name: .[0].node.name, color: (.[0].node.color // "#8b949e"), size: (map(.size) | add)})
  | sort_by(-.size) as $all
  | ($all | map(.size) | add) as $total
  | ($all[10:] | map(.size) | add // 0) as $rest
  | ($all[0:10] + (if $rest > 0 then [{name: "Other", color: "#8b949e", size: $rest}] else [] end)) as $items
  | (($items | length + 1) / 2 | floor) as $rows
  | (78 + $rows * 22 + 6) as $height
  | (reduce $items[] as $i ({x: 12, bars: ""};
      (456 * $i.size / $total) as $w
      | .bars += "<rect x=\"\(.x)\" y=\"40\" width=\"\($w)\" height=\"12\" fill=\"\($i.color)\"/>"
      | .x += $w)) as $bar
  | ($items | to_entries | map(
      .key as $k | .value as $i
      | (12 + ($k / $rows | floor) * 232) as $x
      | (82 + ($k % $rows) * 22) as $y
      | "<circle cx=\"\($x + 5)\" cy=\"\($y - 4)\" r=\"5\" fill=\"\($i.color)\"/>"
        + "<text x=\"\($x + 18)\" y=\"\($y)\">\($i.name | esc)</text>"
        + "<text class=\"pct\" x=\"\($x + 212)\" y=\"\($y)\" text-anchor=\"end\">\(pct($i.size; $total))</text>"
    ) | join("")) as $list
  | "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"480\" height=\"\($height)\" viewBox=\"0 0 480 \($height)\">"
    + "<style>text{font:13px -apple-system,BlinkMacSystemFont,\"Segoe UI\",Helvetica,Arial,sans-serif;fill:#777}"
    + ".title{font-size:16px;font-weight:600;fill:#0366d6}.pct{fill:#999}</style>"
    + "<text class=\"title\" x=\"12\" y=\"24\">Most used languages</text>"
    + "<clipPath id=\"r\"><rect x=\"12\" y=\"40\" width=\"456\" height=\"12\" rx=\"6\"/></clipPath>"
    + "<g clip-path=\"url(#r)\">\($bar.bars)</g>"
    + $list
    + "</svg>"
' > "$out"
