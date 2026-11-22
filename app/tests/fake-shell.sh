#!/bin/bash
# A stand-in for omarchy-shell in the tests: answers appModel and app <id> like the omaplace service, from the made-up
# fixture model, and logs each request's op and args to $FAKE_RT/requests.log. FAKE_MODE: missing (no plugin), old (no
# app method), contract (another contract), pending (open answers pending, then the model goes idle).
set -u
rt=$FAKE_RT
fixture=$FAKE_FIXTURE
mode=${FAKE_MODE:-}
target=$1 method=$2
[ "$mode" = missing ] && { echo "Target not found." >&2; exit 1; }
[ "$target" = io.github.felipecpaiva.omaplace ] || { echo "Target not found." >&2; exit 1; }
[ "$mode" = old ] && { echo "Function not found." >&2; exit 1; }
seqfile=$rt/seq
seq=$(( $(cat "$seqfile" 2>/dev/null || echo 1) + 1 ))
echo $seq > "$seqfile"
model() { python3 -c 'import json,sys; m=json.load(open(sys.argv[1])); m["seq"]=int(sys.argv[2]); m["busy"]=sys.argv[3]=="1"; m["contract"]=int(sys.argv[4]); print(json.dumps(m))' "$fixture" "$1" "$2" "${3:-1}"; }
contract=1
[ "$mode" = contract ] && contract=2
case $method in
  appModel)
    model $seq 0 $contract > "$rt/app-model.json.tmp" && mv "$rt/app-model.json.tmp" "$rt/app-model.json"
    echo "{\"ok\":true,\"contract\":$contract}" ;;
  app)
    id=$3
    req=$(cat "$rt/app-$id.json")
    rm -f "$rt/app-$id.json"
    echo "$req" >> "$rt/requests.log"
    op=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["op"])' "$req")
    answer='{"ok":true}'
    busy=0
    if [ "$mode" = pending ] && [ "$op" = open ]; then
      answer='{"ok":true,"pending":true,"req":"q1-1"}'; busy=1
      # the service finishes later and pushes an idle model
      ( sleep 0.4; model $((seq + 50)) 0 > "$rt/app-model.json.tmp" && mv "$rt/app-model.json.tmp" "$rt/app-model.json" ) &
    fi
    [ "$op" = result ] && answer='{"ok":true,"state":"done","placed":2}'
    python3 -c 'import json,sys; print(json.dumps({"contract":1,"id":sys.argv[1],"answer":json.loads(sys.argv[2]),"model":json.loads(sys.argv[3])}))' \
      "$id" "$answer" "$(model $seq $busy)" > "$rt/app-$id-reply.json"
    echo "$answer" ;;
  *) echo "Function not found." >&2; exit 1 ;;
esac
