# Remaining TTE Effects to Record

## Status
10/36 effects recorded. 26 remaining.

## Already recorded
beams, decrypt, blackhole, fireworks, rain, waves, crumble, spotlights, matrix, sweep

## Remaining effects
1. binarypath
2. bouncyballs
3. bubbles
4. burn
5. colorshift
6. errorcorrect
7. expand
8. fireworks
9. highlight
10. laseretch
11. middleout
12. orbittingvolley
13. overflow
14. pour
15. print
16. randomsequence
17. rings
18. scattered
19. slice
20. slide
21. smoke
22. spray
23. swarm
24. synthgrid
25. thunderstorm
26. unstable
27. vhstape
28. wipe

## Pipeline (proven working)

### 1. Generate VHS tape file per effect
```bash
printf 'Output clips/%s_long.mp4\nSet Width 2880\nSet Height 1864\nSet FontSize 32\nSet Padding 0\nSet Theme { "background": "#000000", "foreground": "#ffffff" }\nSet Shell zsh\nSet TypingSpeed 0\n\nHide\nType "clear && tte -i /Users/austin/screensaver/screensaver.txt --frame-rate 60 --canvas-width 0 --canvas-height 0 --anchor-canvas c --anchor-text c --no-eol --no-restore-cursor EFFECT ; sleep 999"\nEnter\nShow\nSleep 15s\n' > clips/EFFECT_long.tape
```

### 2. Record
```bash
vhs clips/EFFECT_long.tape
```

### 3. Auto-trim (remove trailing static frames)
```bash
freeze=$(ffmpeg -i clips/EFFECT_long.mp4 -vf "freezedetect=n=0.003:d=0.5" -f null - 2>&1 | grep "freeze_start" | tail -1 | sed 's/.*freeze_start: //')
ffmpeg -y -i clips/EFFECT_long.mp4 -t $(echo "$freeze + 1" | bc) -c copy clips/EFFECT_final.mp4
```

### 4. Concatenate all effects
```bash
# Create concat_list.txt with all *_final.mp4 files
ffmpeg -y -f concat -safe 0 -i clips/concat_list.txt -c copy clips/all_effects.mp4
```

### 5. Composite over background
```bash
duration=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 clips/all_effects.mp4)
ffmpeg -y \
  -i "/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS/6D6834A4-2F0F-479A-B053-7D4DC5CB8EB7.mov" \
  -i clips/all_effects.mp4 \
  -filter_complex "[0:v]fps=25,scale=in_range=tv:out_range=pc,format=yuv420p[bg];[1:v]scale=3840:2160,colorkey=color=black:similarity=0.05:blend=0.0[overlay];[bg][overlay]overlay=0:0:shortest=1" \
  -pix_fmt yuv420p -color_range pc -c:v libx264 -crf 18 \
  clips/screensaver_final.mp4
```
