cd /mnt/d/WorkSpace/RabbitHole/lib
for f in *.sh; do
    echo "Fixing $f"
    tr -d '\r' < "$f" > "$f.tmp"
    mv "$f.tmp" "$f"
done
