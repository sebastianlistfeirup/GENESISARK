cap () 
{ 
    timeout 120 xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-method gl_compatibility --resolution 1600x900 -- --capture=evidence/shots/$1.png --scene=$2 --setup=$3 --wait=${5:-90} ${4:+--action=$4} 2>&1 | grep -E "SCRIPT ERROR|Parse Error|CAPTURED|^ERROR" | grep -v "status < 0" | sort -u | head -20
}
