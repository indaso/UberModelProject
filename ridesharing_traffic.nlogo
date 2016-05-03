globals
[
  grid-x-inc
  grid-y-inc
  acceleration             ;; the constant that controls how much a car speeds up or slows down by if
                           ;; it is to accelerate or decelerate
  phase                    ;; keeps track of the phase
  num-cars-stopped         ;; the number of cars that are stopped during a single pass thru the go procedure
  current-light            ;; the currently selected light

  ;; patch agentsets
  intersections ;; agentset containing the patches that are intersections
  roads         ;; agentset containing the patches that are roads

  ;;locations
  campus        ;; agentset containing the patches that are campus
  library       ;; agentset containing the patches that are library
  club          ;; agentset containing the patches that are club
  work          ;; agentset containing the patches that are work
  arcade        ;; agentset containing the patches that are arcade
  locations     ;; list containing possible locations
  surge-pricing-active? ;;

  ;;points
  pickup-points      ;; list of x,y points containing places where you can pick up
]

breed [taxis taxi]
breed [ubers uber]
breed [people person]
breed [ cars car ]

taxis-own [
  speed             ;; the speed of the turtle
  status            ;; "CALLED", "HAS_PASSENGER", "NO_PASSENGER"
  destination       ;; destination
  wait-time         ;; the amount of time since the last time a turtle has moved
]

ubers-own [
  speed             ;; the speed of the turtle
  status            ;; "CALLED", "HAS_PASSENGER", "NO_PASSENGER"
  destination       ;; destination
  wait-time         ;; the amount of time since the last time a turtle has moved
]

people-own [
 location
 preferred-car
 want-car?
 in-car?
]

patches-own
[
  intersection?   ;; true if the patch is at the intersection of two roads
  green-light-up? ;; true if the green light is above the intersection.  otherwise, false.
                  ;; false for a non-intersection patches.
  my-row          ;; the row of the intersection counting from the upper left corner of the
                  ;; world.  -1 for non-intersection patches.
  my-column       ;; the column of the intersection counting from the upper left corner of the
                  ;; world.  -1 for non-intersection patches.
  my-phase        ;; the phase for the intersection.  -1 for non-intersection patches.
  auto?           ;; whether or not this intersection will switch automatically.
                  ;; false for non-intersection patches.
  direction       ;; list of ways a car can be oriented, roads have 1, intersections, may have 2
                  ;; non-roads have 0
]


;;;;;;;;;;;;;;;;;;;;;;
;; Setup Procedures ;;
;;;;;;;;;;;;;;;;;;;;;;

;; Initialize the display by giving the global and patch variables initial values.
;; Create num-cars of turtles if there are enough road patches for one turtle to
;; be created per road patch. Set up the plots.
to setup
  clear-all
  setup-globals
  set grid-y-inc 6
  set grid-x-inc 6
  ;; First we ask the patches to draw themselves and set up a few variables
  setup-worldsize
  setup-patches
  setup-locations
  setup-pickup-points
  set locations [ "campus" "library" "club" "work" "arcade" ]


  set-default-shape taxis "car"
  set-default-shape ubers "car"
  set-default-shape cars "car"
  set-default-shape people "person"
  ;; Now create the turtles and have each created turtle call the functions setup-cars and set-car-color

  create-taxis num-taxis
  [
    setup-taxis
    record-data
  ]

  if ridesharing-allowed?
  [
    create-ubers num-ubers
    [
      setup-ubers
      record-data
    ]
  ]

  ;; give the turtles an initial speed
  ask taxis [ set-car-speed ]
  set surge-pricing-active? false
  create-people num-people
  ask people [
    let p-id who
    set color red
    setup-people-pos p-id
    set want-car? false
    set in-car? false
  ]

  initialize-demand

  reset-ticks
end

to setup-worldsize
  resize-world 0 30 0 30
end

;; Initialize the global variables to appropriate values
to setup-globals
  set current-light nobody ;; just for now, since there are no lights yet
  set phase 0
  set num-cars-stopped 0

  ;; don't make acceleration 0.1 since we could get a rounding error and end up on a patch boundary
  set acceleration 0.099
end

;; Make the patches have appropriate colors, set up the roads and intersections agentsets,
;; and initialize the traffic lights to one setting
to setup-patches
  ;; initialize the patch-owned variables and color the patches to a base-color
  ask patches
  [
    set intersection? false
    set auto? false
    set green-light-up? true
    set my-row -1
    set my-column -1
    set my-phase -1
    set pcolor brown + 3
    set direction []
  ]

  ;; initialize the global variables that hold patch agentsets
  set roads patches with
    [(pxcor mod grid-x-inc = 0) or (pycor mod grid-y-inc = 0)]
  set intersections roads with
    [(pxcor mod grid-x-inc = 0) and (pycor mod grid-y-inc = 0)]

  ;;set direction that a car my drive on the road
  ask roads [
    ifelse (pxcor mod 6 = 0)
    [ ;; traveling vertically
      ifelse ((pxcor / 6 = 0) or (pxcor / 6 = 2) or (pxcor / 6 = 4))
      [set direction [0 180]]    ;; on road heading down
      [set direction [0 180]]   ;; on road heading up
    ] [ ;; traveling horizontally
    ifelse ((pycor / 6 = 0) or (pycor / 6 = 2) or (pycor / 6 = 4))
    [set direction [90 270]]    ;; on road heading left
    [set direction [90 270]]   ;; on road heading right
    ]
  ]

  ;; set inner intersections to have multiple directions so cars will turn
  ;; outer intersections should turn so cars dont exit model
  ask intersections [
    if ((pxcor / 6 = 2) or (pxcor / 6 = 4) or (pxcor / 6 = 1) or (pxcor / 6 = 3))
      [
        if ((pycor / 6 = 1) or (pycor / 6 = 3) or (pycor / 6 = 2) or (pycor / 6 = 4))
            [set direction [0 90 180 270]]
        if (pycor / 6 = 0)
            [set direction [0 90 270]]
         if (pycor / 6 = 5)
            [set direction [90 180 270]]
      ]
     if (pxcor / 6 = 0)
     [
        if ((pycor / 6 = 1) or (pycor / 6 = 3) or (pycor / 6 = 2) or (pycor / 6 = 4))
           [set direction [0 90 180]]
        if (pycor / 6 = 5)
           [set direction [180 90]]
        if (pycor / 6 = 0)
           [set direction [0 90]]
      ]
     if (pxcor / 6 = 5)
     [
        if ((pycor / 6 = 1) or (pycor / 6 = 3) or (pycor / 6 = 2) or (pycor / 6 = 4))
           [set direction [0 180 270]]
        if (pycor / 6 = 5)
           [set direction [180 270]]
        if (pycor / 6 = 0)
           [set direction [0 270]]
     ]
  ]

  ask roads [ set pcolor white ]
  setup-intersections
end

;; Give the intersections appropriate values for the intersection?, my-row, and my-column
;; patch variables.  Make all the traffic lights start off so that the lights are red
;; horizontally and green vertically.
to setup-intersections
  ask intersections
  [
    set intersection? true
    set green-light-up? true
    set my-phase 0
    set auto? true
    set my-row pycor / grid-y-inc
    set my-column pxcor / grid-x-inc
    set-signal-colors
  ]
end

;; Initialize the turtle variables to appropriate values and place the turtle on an empty road patch.
to setup-taxis
  set speed 0
  set wait-time 0
  set color yellow
  set status "NO_PASSENGER"
  set destination -1
  put-on-empty-road

  ifelse (xcor mod 6 = 0)   ;;set heading in directions
  [ ;; traveling vertically
    ifelse (random 2 = 0)
    [set heading 0]
    [set heading 180]
  ] [ ;; traveling horizontally
    ifelse (random 2 = 0)
    [set heading 270]
    [set heading 90]
  ]
end

;; Initialize the turtle variables to appropriate values and place the turtle on an empty road patch.
to setup-ubers
  set speed 0
  set wait-time 0
  set color black
  put-on-empty-road
  set status "NO_PASSENGER"

  ifelse (xcor mod 6 = 0)   ;;set heading in directions
  [ ;; traveling vertically
    ifelse (random 2 = 0)
    [set heading 0]
    [set heading 180]
  ] [ ;; traveling horizontally
    ifelse (random 2 = 0)
    [set heading 270]
    [set heading 90]
  ]

end

;; Find a road patch without any cars on it and place the car there.
to put-on-empty-road  ;; turtle procedure
  move-to one-of roads with [not any? cars-on self]
end

;; look at user's preference and decide what car they want
to pick-car-type
  if (ridesharing-allowed? and preferred-car = "Uber")
  [
    ifelse(surge-pricing-active?)
    [
      ifelse(uber-rate > taxi-rate)
      [ set preferred-car "Taxi" set color blue + 2]
      [ set preferred-car "Uber" set color green ]
    ]
    [ set preferred-car "Uber" set color green ]
  ]
end

;; Assign a taxi or Uber to a rider
to assign-car-preference
  ifelse (ridesharing-allowed? and random 10 < uber-preference)
  [ set preferred-car "Uber" set color green ]
  [ set preferred-car "Taxi" set color blue + 2 ]
  if (random 10 < 1)
  [ set preferred-car "Other"
    set want-car? false set color red]
  pick-car-type
end

;; initialize random num-people to wanting an uber
to initialize-demand
  ask n-of (num-people / 2) people
  [
    initialize-random-location
    assign-car-preference
    set want-car? true
  ]

end

;; set random location
to initialize-random-location
  let loc_index random 5
  set location item loc_index locations
end

to-report get-dropoff-location-point [ loc ]
  if(loc = "campus") [ report [ 18 12 ] ]
  if(loc = "arcade") [ report [ 6 25 ] ]
  if(loc = "club") [ report [ 30 1 ] ]
  if(loc = "library") [ report [ 30 25 ] ]
  if(loc = "work") [ report [ 6 1 ] ]
end

to setup-locations
  set work patches with [pxcor < min-pxcor + floor(grid-x-inc) and pxcor > min-pxcor and pycor < min-pycor + floor(grid-y-inc) and pycor > min-pycor]
  set arcade patches with [pxcor < min-pxcor + floor(grid-x-inc) and pxcor > min-pxcor and pycor < max-pycor and pycor > max-pycor - floor(grid-y-inc)]
  set club patches with [pxcor < max-pxcor and pxcor >= max-pxcor - floor(grid-x-inc - 1) and pycor < min-pycor + floor(grid-y-inc) and pycor > min-pycor]
  set library patches with [pxcor < max-pxcor and pxcor >= max-pxcor - floor(grid-x-inc - 1) and pycor < max-pycor and pycor > max-pycor - floor(grid-y-inc)]
  set campus patches with [pxcor < 18 and pxcor > 18 - 6 and pycor < 18 and pycor > 18 - 6]
  ask campus [ set pcolor orange ]
  ask arcade [ set pcolor blue ]
  ask club [ set pcolor green - 3]
  ask library [ set pcolor yellow ]
  ask work [ set pcolor grey ]
end

;; set up initial positions of persons
to setup-people-pos [per]
    let in-road true
    ;; if in road, keep looping until coord is found that is not
    ;; in the road
    while [in-road] [
      set in-road false
      setxy floor(random-xcor) floor(random-ycor)
      ask roads [
        if ([xcor] of turtle per = pxcor and [ycor] of turtle per = pycor)
        [set in-road true]
      ]
    ]
end

;; iterate through each pickup coordinate and create a list of points lists
to setup-pickup-points
  set pickup-points []
  let point []
  foreach [5 11 17 23 29] [
    let x ?
    foreach [25 19 13 7 1] [
      let y ?
      set point lput x point
      set point lput y point
      set pickup-points lput point pickup-points
      set point []
    ]
  ]
end

;; move the person to the pickup point to get a ride
to move-to-pickup-point
  let point get-closest-pickup-point
  setxy item 0 point item 1 point
end

;; find the closest pickup point to the person
to-report get-closest-pickup-point
  let mindist 1000000
  let closest-point []
  foreach pickup-points [
    let point ?
    let dist distancexy item 0 point item 1 point
    if(dist < mindist)
    [
      set mindist dist
      set closest-point point
    ]
  ]
  report closest-point
end

;; get closest uber
to-report get-closest-uber
  let mindist 1000000
  let empty-ubers ubers with [ status = "NO_PASSENGER" ]
  if (not any? empty-ubers)
  [ report no-turtles ]
  let closest-uber one-of empty-ubers
  ask empty-ubers [
    let dist distancexy xcor ycor
    if(dist < mindist)
    [
      set mindist dist
      set closest-uber self
    ]
  ]
  create-link-with closest-uber
  report closest-uber
end

;;;;;;;;;;;;;;;;;;;;;;;;
;; Runtime Procedures ;;
;;;;;;;;;;;;;;;;;;;;;;;;

;; Run the simulation
to go
  ;; have the intersections change their color
  set-signals
  set num-cars-stopped 0


  ask people [
   ;testing code------
   ;;set want-car? true
   ;;set preferred-car "Taxi"
   if (want-car?) [    ;; want-car?=true -->Person is waiting for car and check if car is nearby
     ifelse (preferred-car = "Taxi") [
       assign-taxi
     ]
     [ ;;preferred-car = "Uber"
       assign-uber
     ]
   ]

   ;;if ((not want-car?) and (not in-car?) and count my-links = 0) [
     ;; count added to differentiate between not wanting car and being assigned
     ;; versus not wanting car and not being assigned

        ;;dynamic ask of demand --> assign-car-preference
          ;; ask potential riders to move to pickup point
           ; move-to-pickup-point
        ;;if (preferred-car = "Uber") [ assign-uber ]
        ;;if (preferred-car = "Taxi") [ assign-taxi ]
        ;;if [preferred-car = "None"] --> Do Nothing ( Done since we do nothing )
   ;;]

   if (in-car?) [
     ;;if arrived at destination --> "Drop off person" or "Pick up person"
   ]
  ]


  ;; set the turtles speed for this time thru the procedure, move them forward their speed,
  ;; record data for plotting, and set the color of the turtles to an appropriate color
  ;; based on their speed
  ask taxis [
    ;; go through 3 statuses
    ifelse (status = "CALLED" )
    [
      move-toward-destination destination
      if (distancexy item 0 destination item 1 destination = 1)
      [ pickup ] ;; also add pick-up command (tie and move)
    ]
    [
      ifelse (status = "HAS_PASSENGER")
      [
        move-toward-destination destination
        if (distancexy item 0 destination item 1 destination = 1)
        [ dropoff ] ;; drop-off command (unlink and place person on location grid (setxy one-of patches xcor ycor))
      ]
      [ move-random ]
    ]
  ]

  ask ubers [
    ;; go through 3 statuses
    ifelse (status = "CALLED" )
    [
      move-toward-destination destination
      if (distancexy item 0 destination item 1 destination = 1)
      [ pickup ] ;; also add pick-up command (tie and move)
    ]
    [
      ifelse (status = "HAS_PASSENGER")
      [
        move-toward-destination destination
        if (distancexy item 0 destination item 1 destination = 1)
        [ dropoff ] ;; drop-off command (unlink and place person on location grid (setxy one-of patches xcor ycor))
      ]
      [ move-random ]
    ]
  ]

  ;; update the phase and the global clock
  next-phase
  tick
end

;; pickup person and
to pickup
  set status "HAS_PASSENGER"
  ask my-links [
    set hidden? true
    tie
    ;set color green
  ]
  let passenger [ other-end ] of one-of my-links
  let point-destination get-dropoff-location-point [location] of passenger
  set destination point-destination

  ask passenger [
    set hidden? true
    set in-car? true
  ]
end

to dropoff
  set status "NO_PASSENGER"
  let passenger [ other-end ] of one-of my-links
  ask my-links [
    set hidden? false
    untie
    die
    ;set color yellow
  ]
  ;let point-destination get-dropoff-location-point [location] of passenger
  ;set destination point-destination

  ask passenger [
    set hidden? false
    set color black
    set in-car? false
    if ( location = "campus" ) [ move-to one-of campus ]
    if ( location = "library" ) [ move-to one-of library ]
    if ( location = "club" ) [ move-to one-of club ]
    if ( location = "work" ) [ move-to one-of work ]
    if ( location = "arcade" ) [ move-to one-of arcade ]
  ]
end

to assign-uber
  let curr-per self
  let pickup-point get-closest-pickup-point
  move-to-pickup-point
  let closest-uber get-closest-uber
  ask closest-uber [
    set status "CALLED"
    set destination pickup-point
    ask curr-per [
      set want-car? false
    ]
  ]
end

to assign-taxi
  let curr-person self
  let pickup-point get-closest-pickup-point
  move-to-pickup-point
  let empty-taxi one-of taxis in-radius 4 with [ status = "NO_PASSENGER" ]
  if empty-taxi != nobody [
    ask empty-taxi [ ;;if there is a taxi nearby --> assign person to be in taxi and taxi to have person
      create-link-with curr-person
      set status "CALLED"
      let person_location [location] of curr-person
      set destination pickup-point
      ask curr-person [
        set want-car? false
      ]
    ]
  ]
end

;; Uber and Taxi Related Procedures for GO ----------------------------------------
to move-toward-destination [dest_points]
   set-car-speed
   let step 1
   while [step <= speed] [
     let turnlist (possible-turns direction heading)
     ;;Case 1: If not intersection, drive straight
     ifelse ((length turnlist) = 1) [
       set heading (item 0 turnlist)
     ] [ ;;Case 2: At intersection, choose a random path that takes you closer to your destination
       let closerturns closer_turns xcor ycor dest_points
       let choices []
       foreach closerturns [
         if (member? ? turnlist) [set choices lput ? choices]
       ]
       if (not (empty? choices)) [set heading item (random length choices) choices]
     ]
     fd 1
     set step (step + 1)
   ]
end

to-report closer_turns [x y dest_points]
  let dest_x (item 0 dest_points)
  let dest_y (item 1 dest_points)
  let turns []

  if (dest_x > x) [ set turns lput 90 turns]
  if (dest_x < x) [ set turns lput 270 turns ]
  if (dest_y > y) [ set turns lput 0 turns ]
  if (dest_y < y) [ set turns lput 180 turns ]

  report turns
end

to move-random
    set-car-speed
    ;;check if car will pass an intersection and randomly change direction turtle is heading
    let step 1
    while [step <= speed] [
       ;; set direction of heading
       let turnlist (possible-turns direction heading)
       set heading (item (random length turnlist) turnlist)
       fd 1
       set step (step + 1)
    ]
    record-data
end

to-report possible-turns [all-turns prev]
  let turnlist []
  foreach all-turns [
   if ((? + 180) != prev and (? - 180) != prev) ;;don't let cars reverse directions
   [set turnlist lput ? turnlist]
  ]
  report turnlist
end



;; have the traffic lights change color if phase equals each intersections' my-phase
to set-signals
  ask intersections with [auto? and phase = floor ((my-phase * ticks-per-cycle) / 100)]
  [
    set green-light-up? (not green-light-up?)
    set-signal-colors
  ]
end

;; This procedure checks the variable green-light-up? at each intersection and sets the
;; traffic lights to have the green light up or the green light to the left.
to set-signal-colors  ;; intersection (patch) procedure
  ;ifelse ridesharing-allowed?
  ;[
    ifelse green-light-up? [
      if (pxcor != 0) [ask patch-at -1 0 [ set pcolor red ]]
      if (pycor != 30) [ask patch-at 0 1 [ set pcolor green ]]
    ] [
      if (pxcor != 0) [ask patch-at -1 0 [ set pcolor green ]]
      if (pycor != 30) [ask patch-at 0 1 [ set pcolor red ]]
    ]
  ;]
  ;[
  ;  ask patch-at -1 0 [ set pcolor white ]
  ;  ask patch-at 0 1 [ set pcolor white ]
  ;]
end

;; set the turtles' speed based on whether they are at a red traffic light or the speed of the
;; turtle (if any) on the patch in front of them
to set-car-speed  ;; turtle procedure
  ifelse pcolor = red
  [ set speed 0 ]
  [
    ifelse (heading = 0 or heading = 180)
         [ set-speed 0 1 ]
         [ set-speed 1 0]
  ]
end

;; set the speed variable of the car to an appropriate value (not exceeding the
;; speed limit) based on whether there are cars on the patch in front of the car
to set-speed [ delta-x delta-y ]  ;; turtle procedure
  ;; get the turtles on the patch in front of the turtle
  let cars-ahead cars-at delta-x delta-y

  ;; if there are turtles in front of the turtle, slow down
  ;; otherwise, speed up
  ifelse any? cars-ahead
  [
    ;;ifelse any? (turtles-ahead with [ up-car? != [up-car?] of myself ])
    ifelse any? (cars-ahead with [ true != [true] of myself ])
    [
      set speed 0
    ]
    [
      set speed [speed] of one-of cars-ahead
      slow-down
    ]
  ]
  [ speed-up ]
end

;; decrease the speed of the turtle
to slow-down  ;; turtle procedure
  ifelse speed <= 0  ;;if speed < 0
  [ set speed 0 ]
  [ set speed speed - acceleration ]
end

;; increase the speed of the turtle
to speed-up  ;; turtle procedure
  ifelse speed > speed-limit
  [ set speed speed-limit ]
  [ set speed speed + acceleration ]
end

;; keep track of the number of stopped turtles and the amount of time a turtle has been stopped
;; if its speed is 0
to record-data  ;; turtle procedure
  ifelse speed = 0
  [
    set num-cars-stopped num-cars-stopped + 1
    set wait-time wait-time + 1
  ]
  [ set wait-time 0 ]
end



;; cycles phase to the next appropriate value
to next-phase
  ;; The phase cycles from 0 to ticks-per-cycle, then starts over.
  set phase phase + 1
  if phase mod ticks-per-cycle = 0
    [ set phase 0 ]
end


;; test methods

to test-get-closest-uber
  ask person 131 [ setxy 1 29 set want-car? true set preferred-car "Uber" ]
  ask uber 16 [ setxy 6 30 ]
  let pickup-point []
  let closest-uber one-of ubers
  ask person 131 [
    set pickup-point get-closest-pickup-point
    set closest-uber get-closest-uber
    ask closest-uber [
      set destination pickup-point
      set status "CALLED"
      ]
  ]
end

; Copyright 2003 Uri Wilensky.
; See Info tab for full copyright and license.
@#$#@#$#@
GRAPHICS-WINDOW
326
10
668
373
-1
-1
10.71
1
12
1
1
1
0
1
1
1
0
30
0
30
1
1
1
ticks
30.0

PLOT
675
351
893
515
Average Wait Time of Cars
Time
Average Wait
0.0
100.0
0.0
5.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot mean [wait-time] of taxis"

PLOT
676
181
892
346
Average Speed of Cars
Time
Average Speed
0.0
100.0
0.0
1.0
true
false
"set-plot-y-range 0 speed-limit" ""
PENS
"default" 1.0 0 -16777216 true "" "plot mean [speed] of taxis"

SWITCH
10
219
197
252
ridesharing-allowed?
ridesharing-allowed?
0
1
-1000

SLIDER
10
117
184
150
num-ubers
num-ubers
0
100
4
1
1
NIL
HORIZONTAL

PLOT
676
10
890
174
Stopped Cars
Time
Stopped Cars
0.0
100.0
0.0
100.0
true
false
"set-plot-y-range 0 num-cars" ""
PENS
"default" 1.0 0 -16777216 true "" "plot num-cars-stopped"

BUTTON
225
305
289
338
Go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
206
81
290
114
Setup
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
9
289
163
322
speed-limit
speed-limit
0.1
1
1
0.1
1
NIL
HORIZONTAL

SLIDER
9
255
163
288
ticks-per-cycle
ticks-per-cycle
1
100
28
1
1
NIL
HORIZONTAL

SLIDER
11
85
183
118
num-taxis
num-taxis
0
100
2
1
1
NIL
HORIZONTAL

SLIDER
9
330
181
363
uber-rate
uber-rate
5
12
7.8
0.01
1
$
HORIZONTAL

SLIDER
10
372
182
405
taxi-rate
taxi-rate
8
18
12.14
0.01
1
$
HORIZONTAL

SLIDER
11
44
183
77
num-people
num-people
0
100
29
1
1
NIL
HORIZONTAL

SLIDER
11
164
124
197
cost-tolerance
cost-tolerance
1
10
6
1
1
NIL
HORIZONTAL

SLIDER
140
163
312
196
uber-preference
uber-preference
0
10
9
1
1
NIL
HORIZONTAL

@#$#@#$#@
## WHAT IS IT?

This is a model of traffic moving in a city grid. It allows you to control traffic lights and global variables, such as the speed limit and the number of cars, and explore traffic dynamics.

Try to develop strategies to improve traffic and to understand the different ways to measure the quality of traffic.

## HOW IT WORKS

Each time step, the cars attempt to move forward at their current speed.  If their current speed is less than the speed limit and there is no car directly in front of them, they accelerate.  If there is a slower car in front of them, they match the speed of the slower car and deccelerate.  If there is a red light or a stopped car in front of them, they stop.

There are two different ways the lights can change.  First, the user can change any light at any time by making the light current, and then clicking CHANGE LIGHT.  Second, lights can change automatically, once per cycle.  Initially, all lights will automatically change at the beginning of each cycle.

## HOW TO USE IT

Change the traffic grid (using the sliders GRID-SIZE-X and GRID-SIZE-Y) to make the desired number of lights.  Change any other of the settings that you would like to change.  Press the SETUP button.

At this time, you may configure the lights however you like, with any combination of auto/manual and any phase. Changes to the state of the current light are made using the CURRENT-AUTO?, CURRENT-PHASE and CHANGE LIGHT controls.  You may select the current intersection using the SELECT INTERSECTION control.  See below for details.

Start the simulation by pressing the GO button.  You may continue to make changes to the lights while the simulation is running.

### Buttons

SETUP - generates a new traffic grid based on the current GRID-SIZE-X and GRID-SIZE-Y and NUM-CARS number of cars.  This also clears all the plots. All lights are set to auto, and all phases are set to 0.
GO - runs the simulation indefinitely
CHANGE LIGHT - changes the direction traffic may flow through the current light. A light can be changed manually even if it is operating in auto mode.
SELECT INTERSECTION - allows you to select a new "current" light. When this button is depressed, click in the intersection which you would like to make current. When you've selected an intersection, the "current" label will move to the new intersection and this button will automatically pop up.

### Sliders

SPEED-LIMIT - sets the maximum speed for the cars
NUM-CARS - the number of cars in the simulation (you must press the SETUP button to see the change)
TICKS-PER-CYCLE - sets the number of ticks that will elapse for each cycle.  This has no effect on manual lights.  This allows you to increase or decrease the granularity with which lights can automatically change.
GRID-SIZE-X - sets the number of vertical roads there are (you must press the SETUP button to see the change)
GRID-SIZE-Y - sets the number of horizontal roads there are (you must press the SETUP button to see the change)
CURRENT-PHASE - controls when the current light changes, if it is in auto mode. The slider value represents the percentage of the way through each cycle at which the light should change. So, if the TICKS-PER-CYCLE is 20 and CURRENT-PHASE is 75%, the current light will switch at tick 15 of each cycle.

### Switches

POWER? - toggles the presence of traffic lights
CURRENT-AUTO? - toggles the current light between automatic mode, where it changes once per cycle (according to CURRENT-PHASE), and manual, in which you directly control it with CHANGE LIGHT.

### Plots

STOPPED CARS - displays the number of stopped cars over time
AVERAGE SPEED OF CARS - displays the average speed of cars over time
AVERAGE WAIT TIME OF CARS - displays the average time cars are stopped over time

## THINGS TO NOTICE

When cars have stopped at a traffic light, and then they start moving again, the traffic jam will move backwards even though the cars are moving forwards.  Why is this?

When POWER? is turned off and there are quite a few cars on the roads, "gridlock" usually occurs after a while.  In fact, gridlock can be so severe that traffic stops completely.  Why is it that no car can move forward and break the gridlock?  Could this happen in the real world?

Gridlock can occur when the power is turned on, as well.  What kinds of situations can lead to gridlock?

## THINGS TO TRY

Try changing the speed limit for the cars.  How does this affect the overall efficiency of the traffic flow?  Are fewer cars stopping for a shorter amount of time?  Is the average speed of the cars higher or lower than before?

Try changing the number of cars on the roads.  Does this affect the efficiency of the traffic flow?

How about changing the speed of the simulation?  Does this affect the efficiency of the traffic flow?

Try running this simulation with all lights automatic.  Is it harder to make the traffic move well using this scheme than controlling one light manually?  Why?

Try running this simulation with all lights automatic.  Try to find a way of setting the phases of the traffic lights so that the average speed of the cars is the highest.  Now try to minimize the number of stopped cars.  Now try to decrease the average wait time of the cars.  Is there any correlation between these different metrics?

## EXTENDING THE MODEL

Currently, the maximum speed limit (found in the SPEED-LIMIT slider) for the cars is 1.0.  This is due to the fact that the cars must look ahead the speed that they are traveling to see if there are cars ahead of them.  If there aren't, they speed up.  If there are, they slow down.  Looking ahead for a value greater than 1 is a little bit tricky.  Try implementing the correct behavior for speeds greater than 1.

When a car reaches the edge of the world, it reappears on the other side.  What if it disappeared, and if new cars entered the city at random locations and intervals?

## NETLOGO FEATURES

This model uses two forever buttons which may be active simultaneously, to allow the user to select a new current intersection while the model is running.

It also uses a chooser to allow the user to choose between several different possible plots, or to display all of them at once.

## RELATED MODELS

Traffic Basic simulates the flow of a single lane of traffic in one direction
Traffic 2 Lanes adds a second lane of traffic
Traffic Intersection simulates a single intersection

The HubNet activity Gridlock has very similar functionality but allows a group of users to control the cars in a participatory fashion.

## HOW TO CITE

If you mention this model or the NetLogo software in a publication, we ask that you include the citations below.

For the model itself:

* Wilensky, U. (2003).  NetLogo Traffic Grid model.  http://ccl.northwestern.edu/netlogo/models/TrafficGrid.  Center for Connected Learning and Computer-Based Modeling, Northwestern University, Evanston, IL.

Please cite the NetLogo software as:

* Wilensky, U. (1999). NetLogo. http://ccl.northwestern.edu/netlogo/. Center for Connected Learning and Computer-Based Modeling, Northwestern University, Evanston, IL.

## COPYRIGHT AND LICENSE

Copyright 2003 Uri Wilensky.

![CC BY-NC-SA 3.0](http://ccl.northwestern.edu/images/creativecommons/byncsa.png)

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike 3.0 License.  To view a copy of this license, visit https://creativecommons.org/licenses/by-nc-sa/3.0/ or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

Commercial licenses are also available. To inquire about commercial licenses, please contact Uri Wilensky at uri@northwestern.edu.

This model was created as part of the projects: PARTICIPATORY SIMULATIONS: NETWORK-BASED DESIGN FOR SYSTEMS LEARNING IN CLASSROOMS and/or INTEGRATED SIMULATION AND MODELING ENVIRONMENT. The project gratefully acknowledges the support of the National Science Foundation (REPP & ROLE programs) -- grant numbers REC #9814682 and REC-0126227.

<!-- 2003 -->
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
true
0
Polygon -7500403 true true 180 15 164 21 144 39 135 60 132 74 106 87 84 97 63 115 50 141 50 165 60 225 150 285 165 285 225 285 225 15 180 15
Circle -16777216 true false 180 30 90
Circle -16777216 true false 180 180 90
Polygon -16777216 true false 80 138 78 168 135 166 135 91 105 106 96 111 89 120
Circle -7500403 true true 195 195 58
Circle -7500403 true true 195 47 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270

@#$#@#$#@
NetLogo 5.3
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

@#$#@#$#@
0
@#$#@#$#@
