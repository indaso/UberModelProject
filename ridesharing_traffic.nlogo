globals
[
  grid-x-inc
  grid-y-inc
  acceleration             ;; the constant that controls how much a car speeds up or slows down by if
                           ;; it is to accelerate or decelerate
  phase                    ;; keeps track of the phase
  num-cars-stopped         ;; the number of cars that are stopped during a single pass thru the go procedure
  current-light            ;; the currently selected light

  taxis
  ubers

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
  surge-pricing-ratio
  num-cars

  ;;points
  pickup-points      ;; list of x,y points containing places where you can pick up

  ;; Demand correlated with simplified real world traffic volume data
  weekend-traffic
  weekday-traffic

  ticks-per-cycle

  ;; metrics

  total-num-cars    ;; total amount of cars over 24 hours
  min-num-cars      ;; minimum number of cars in an hour
  max-num-cars      ;; maximum number of cars in an hour over the course of a day
  avg-num-cars      ;; average number of cars per hour
  car-stat-list     ;; number of cars in each hour
]

breed [people person]
breed [cars car]

cars-own [
  car-type          ;; "Uber" or "Taxi"
  speed             ;; the speed of the turtle
  status            ;; "CALLED", "HAS_PASSENGER", "NO_PASSENGER"
  destination       ;; destination
  wait-time         ;; the amount of time since the last time a turtle has moved
  surge-price       ;; the multiple of the current fare if demand for Ubers exceeds supply
]

people-own [
 location
 preferred-car
 want-car?
 in-car?
 want-car-count
 max-cost
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
  set weekend-traffic [1 0.5 5 6 8 4]
  set weekday-traffic [2 0.5 2 7 8 4]

  set-default-shape cars "car"
  set-default-shape people "person"

  ;; Now create the turtles and have each created turtle call the functions setup-cars and set-car-color
  set num-cars num-taxis + num-ubers
  create-cars num-taxis
  set taxis cars
  ask taxis
  [
    setup-taxis
    record-data
  ]
  if ridesharing-allowed?
  [
  create-cars num-ubers
  set ubers cars with [ car-type != "Taxi" ]



    ask ubers
    [
      setup-ubers
      record-data
    ]
  ]

  ;; give the turtles an initial speed
  ask taxis [ set-car-speed ]
  set surge-pricing-active? false
  create-people num-people [
    setup-people
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
  set ticks-per-cycle 3
  set car-stat-list []

  ;; don't make acceleration 0.1 since we could get a rounding error and end up on a patch boundary
  set acceleration 1.0
end

to setup-people
    let p-id who
    set color red
    setup-people-pos
    set want-car? false
    set in-car? false
    set want-car-count 0
    set max-cost random-normal ((cost-tolerance * 10) / 100 * 35) 10
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
  set destination []
  set car-type "Taxi"
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
  set destination []
  set status "NO_PASSENGER"
  set car-type "Uber"
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

;; Find a road patch without any cars on it and place the car there.
to put-on-empty-road  ;; turtle procedure
  move-to one-of roads with [not any? cars-on self]
end

;; look at user's preference and decide what car they want based on several factors
to pick-car-type
  let uber-rate calculate-uber-rate
  let taxi-rate calculate-taxi-rate
  if surge-pricing-active?
  [ set uber-rate (uber-rate * surge-pricing-ratio) ]

  if (ridesharing-allowed? and preferred-car = "Uber")
  [
    let destination-rates list uber-rate taxi-rate
    ifelse(min destination-rates < max-cost)
    [
      ifelse(uber-rate > taxi-rate)
      [ set preferred-car "Taxi" set color blue + 2 ]
      [ set preferred-car "Uber" set color green ]
    ]
    [ set want-car? false set color red set preferred-car "Other" stop ]
  ]
end

;; Assign a taxi or Uber to a rider
to assign-car-preference
  set want-car? true
  ifelse (ridesharing-allowed? and random 10 < uber-preference)
  [ set preferred-car "Uber" set color green ]
  [ set preferred-car "Taxi" set color blue + 2 ]
  if (random 10 < 1)
  [ set preferred-car "Other"
    set want-car? false set color red]
  pick-car-type
end

to-report calculate-uber-rate
  let point get-dropoff-location-point [location] of self
  report base-uber-rate + 0.5 * distancexy item 0 point item 1 point
end

to-report calculate-taxi-rate
  let point get-dropoff-location-point [location] of self
  report base-taxi-rate + distancexy item 0 point item 1 point
end

;; initialize random num-people to wanting an uber
to initialize-demand
  ask n-of (num-people / 2) people
  [
    initialize-random-location
    assign-car-preference
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
to setup-people-pos
    let in-road true
    ;; if in road, keep looping until coord is found that is not
    ;; in the road
    while [in-road] [
      set in-road false
      setxy floor(random-xcor) floor(random-ycor)
      ask roads [
        if ([xcor] of myself = pxcor and [ycor] of myself = pycor)
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

to update-surge-pricing
  ;; survey for Uber demand
  let num-people-want-uber count people with [
    preferred-car = "Uber" and want-car? = true
  ]
  ;; survey for Uber availability
  let num-ubers-available count ubers with [ status = "NO_PASSENGER" ]
  ;; set up surge pricing as ratio
  if num-ubers-available = 0
  [ set num-ubers-available 1 ]
  set surge-pricing-ratio num-people-want-uber / num-ubers-available
     ;; show num-people-want-uber
     ;; show num-ubers-available
     ;; show surge-pricing-ratio
  if (surge-pricing-ratio > 1 )
  [ set surge-pricing-active? true ]
  ask ubers [
    ifelse (surge-pricing-active?)
      [ set surge-price surge-pricing-ratio * base-uber-rate ]
      [ set surge-price base-uber-rate ]
  ]
  ;show surge-pricing-ratio
  ;show surge-pricing-ratio * base-uber-rate
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
  if ticks mod 60 = 0 and ridesharing-allowed?
  [ update-surge-pricing ]

  if ticks mod 60 = 0 and ticks != 0
  [ set car-stat-list lput (count cars) car-stat-list ]


  if ticks mod 120 = 0 and ticks != 0 and ridesharing-allowed?
  [ check-uber-demand ]

  if ticks mod 120 = 0 and ticks != 0
  [ check-taxi-demand ]

  if ticks mod 30 = 0 and ticks != 0
  [
    ask people with [ not in-car? and not want-car? and count my-links = 0 ] [
      setup-people-pos
    ]
  ]

  if ticks mod 1440 = 0 and ticks != 0
  [
    set total-num-cars count cars
    set avg-num-cars mean car-stat-list
    set max-num-cars max car-stat-list
    set min-num-cars min car-stat-list
    set total-num-cars sum car-stat-list
    set car-stat-list []
  ]


  let time-of-day (ticks mod 1440)
  ask people [
   if (want-car?) [    ;; want-car?=true -->Person is waiting for car and check if car is nearby
     ifelse (preferred-car = "Taxi") [
       assign-taxi
     ]
     [ ;;preferred-car = "Uber"
       assign-uber
     ]
   ]

   if ((not want-car?) and (not in-car?) and count my-links = 0) [
     ;; count added to differentiate between not wanting car and being assigned versus not wanting car and not being assigned
     if (passenger-want-ride? time-of-day) [
          set want-car-count (want-car-count + 1)
          ;; ask potential riders to move to pic)up point
          set want-car? true
          initialize-random-location
          assign-car-preference
          move-to-pickup-point
      ]
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

  if ridesharing-allowed?
  [
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

  set destination []
end

to assign-uber
  let curr-per self
  ;if color = red [ show "Picking up red passenger" ]
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

to-report passenger-want-ride? [time-of-day]
  let want_ride? false
  if (time-of-day >= 0 and time-of-day < 240)     [set want_ride? (graduated-demand 0) ] ;; 12am - 4am
  if (time-of-day >= 240 and time-of-day < 480)   [set want_ride? (graduated-demand 1) ] ;; 4am - 8am
  if (time-of-day >= 480 and time-of-day < 720)   [set want_ride? (graduated-demand 2) ] ;; 8am - 12pm
  if (time-of-day >= 720 and time-of-day < 960)   [set want_ride? (graduated-demand 3) ] ;; 12pm - 4pm
  if (time-of-day >= 960 and time-of-day < 1200)  [set want_ride? (graduated-demand 4) ] ;; 4pm - 8pm
  if (time-of-day >= 1200 and time-of-day < 1440) [set want_ride? (graduated-demand 5) ] ;; 8pm - 12am
  report want_ride?
end

to-report graduated-demand [ind]
  ;; chance i want a car at 4am on a weekday or weekend is 5% --> Max probability I want a car is 40% at 4pm
  ifelse is_weekday? [
    report (random 1000) < (1 * item ind weekday-traffic)
  ] [
    report (random 1000) < (1 * item ind weekend-traffic)
  ]
end

to check-uber-demand
  let num-people-want-uber count people with [
    preferred-car = "Uber" and want-car? = true
  ]
  ;; survey for Uber availability
  let available-ubers ubers with [ status = "NO_PASSENGER" ]

  let amount num-people-want-uber - count available-ubers
     ;; show num-people-want-uber
     ;; show num-ubers-available
     ;; show surge-pricing-ratio
  ifelse (amount < 0)
  [
    ask n-of abs amount available-ubers [
      die
    ]
  ]
  [
    create-cars amount [
      setup-ubers
    ]
    set ubers cars with [car-type = "Uber"]
  ]
end

to check-taxi-demand
  let num-people-want-taxi count people with [
    preferred-car = "Taxi" and want-car? = true
  ]
  ;; survey for Uber availability
  let available-taxis taxis with [ status = "NO_PASSENGER" ]

  let amount num-people-want-taxi - count available-taxis
     ;; show num-people-want-uber
     ;; show num-ubers-available
     ;; show surge-pricing-ratio
  ifelse (amount < 0)
  [
    ask n-of abs (amount / 5) available-taxis [
      die
    ]
  ]
  [
    create-cars (amount / 5) [
      setup-taxis
    ]
    set taxis cars with [car-type = "Taxi"]
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
      if ((pxcor != 0 or pycor != 0) and (pxcor != 0 or pycor != 30) and (pxcor != 30 or pycor != 0) and (pxcor != 30 or pycor != 30)) [
        if (pxcor != 0) [ask patch-at -1 0 [ set pcolor red ]]
        if (pxcor != 30) [ask patch-at 1 0  [ set pcolor red ]]
        if (pycor != 0) [ask patch-at 0 -1 [ set pcolor green ]]
        if (pycor != 30) [ask patch-at 0 1  [ set pcolor green ]]]
    ] [
     if ((pxcor != 0 or pycor != 0) and (pxcor != 0 or pycor != 30) and (pxcor != 30 or pycor != 0) and (pxcor != 30 or pycor != 30)) [
        if (pxcor != 0) [ask patch-at -1 0 [ set pcolor green ]]
        if (pxcor != 30) [ask patch-at 1 0  [ set pcolor green ]]
        if (pycor != 0) [ask patch-at 0 -1 [ set pcolor red ]]
        if (pycor != 30) [ask patch-at 0 1  [ set pcolor red ]]]
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
  ifelse (pcolor = red and ([pcolor] of patch-at -2 0 != red) and ([pcolor] of patch-at 2 0 != red) and ([pcolor] of patch-at 0 2 != red) and ([pcolor] of patch-at 0 -2 != red))
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
    ifelse any? (cars-ahead with [ heading != [heading] of myself ])
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
  ifelse speed >= speed-limit
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
  ask one-of ubers [ setxy 6 30 ]
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
676
183
894
347
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

SWITCH
11
141
174
174
ridesharing-allowed?
ridesharing-allowed?
0
1
-1000

SLIDER
10
98
186
131
num-ubers
num-ubers
0
30
30
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
252
49
316
82
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
231
13
315
46
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
187
232
315
265
speed-limit
speed-limit
1.0
2
1
0.1
1
NIL
HORIZONTAL

SLIDER
9
56
183
89
num-taxis
num-taxis
0
15
15
1
1
NIL
HORIZONTAL

SLIDER
12
274
187
307
base-uber-rate
base-uber-rate
5
25
5
0.01
1
$
HORIZONTAL

SLIDER
11
316
187
349
base-taxi-rate
base-taxi-rate
10
15
10
0.01
1
$
HORIZONTAL

SLIDER
8
14
180
47
num-people
num-people
0
300
200
1
1
NIL
HORIZONTAL

SLIDER
11
231
175
264
cost-tolerance
cost-tolerance
1
10
5
1
1
NIL
HORIZONTAL

SLIDER
11
186
174
219
uber-preference
uber-preference
0
10
10
1
1
NIL
HORIZONTAL

SWITCH
188
185
315
218
is_weekday?
is_weekday?
1
1
-1000

MONITOR
553
403
696
448
Average Car Demand
mean [want-car-count] of people
3
1
11

MONITOR
565
453
696
498
People who want Taxis
count people with [ preferred-car = \"Taxi\" ]
17
1
11

MONITOR
395
452
558
497
People who want Ubers
count people with [ preferred-car = \"Uber\" ]
17
1
11

MONITOR
396
403
547
448
People who want no cars
count people with [ preferred-car = \"Other\" ]
17
1
11

MONITOR
705
402
806
447
Ubers on Road
count cars with [car-type = \"Uber\"]
17
1
11

MONITOR
293
402
387
447
Empty Ubers
count cars with [ status = \"NO_PASSENGER\" and car-type = \"Uber\" ]
17
1
11

MONITOR
705
453
806
498
Taxis on Road
count cars with [ car-type = \"Taxi\" ]
17
1
11

MONITOR
151
402
283
447
dropped-people
count people with [ color = black ]
17
1
11

MONITOR
257
452
388
497
Total Cars on Road
total-num-cars
17
1
11

MONITOR
146
452
250
497
NIL
min-num-cars
17
1
11

MONITOR
38
403
141
448
NIL
max-num-cars
17
1
11

MONITOR
38
452
141
497
NIL
avg-num-cars
2
1
11

@#$#@#$#@
Wendy Cheng, Jenny Hu, Isobeye Daso
OIDD 325
May 4, 2016

##Monitoring the Traffic Impact of Ridesharing Services

##MODEL OVERVIEW
This model aims to simulate traffic congestion in a simplified city. The model consists of taxi cab, ridesharing car, and passenger agents. Passengers desire to travel to certain destinations within the city and choose to travel by taxi or ridesharing based on their preferences for ridesharing and their willingness to pay. Time of day will affect the demand and presence of cars, which is based on real world traffic data. The model measures the number of cars on the road at a given time across various simulations.


##MOTIVATION FOR THE MODEL
We hope to investigate whether or not ridesharing increases traffic congestion. The main motivation is to study whether our simplified model supports claims by Uber that ridesharing does not significantly increase traffic congestion, or supports the opposite stance taken by established taxi companies. This topic of discussion to relevant to our team because we are all consumers of these different means of transportation. Knowing whether traffic congestion increases or decreases as a result of using Ubers, and therefore encouraging the business of Uber, can allow consumers to travel from one destination to another in an efficient manner at different times of the day.

There is research that supports both positions. Ridesharing has pulled people away from mass transport options, resulting in more vehicles being on the road, which possibly boosts traffic congestion (Bruce, 2014). Alternatively, ridesharing efficiency makes use of otherwise empty seats in cars, this helping to reduce traffic congestion. Harvard Business Review estimates that “shifting about 15 percent of drive-alones to car sharing or ridesharing could save 757 million commuter-hours and about $21 billion in congestion costs annually” (Hower, 2013). Ridesharing cars also tend to carry more passengers on average than cabs: the average trip using ridesharing apps carried 1.8 people compared to the 1.1 with a cab (Bruce, 2014).

We hypothesize that ridesharing does not result in greater traffic congestion because the same passengers who seek to travel to a certain destination would be on the road anyway in one  of the vehicles, whether taxi or ridesharing. We aim to analyze the findings of the model to see whether or not this stance is supported by the model.


##STRUCTURE & ORGANIZATION
The model is a modification of the “Traffic Grid” NetLogo model, which models traffic moving within a city grid. The model provides the capability to control traffic lights and several global variables, such as the speed limit and number of cars. This model is great for expanding upon to explore further traffic dynamics.

The agents in the model include taxi cabs, Uber cars, and passengers. The quantity of each of these agents can be adjusted in the model via sliders. The setup function of our model creates a grid of five by five blocks. The five locations are hardcoded as the top-left, top-right, bottom-left, bottom-right and center.  The number of taxis, Ubers and people are given random locations within the environment such that people are not on the road, and ubers and taxis are on one of the six vertical or six horizontal two way roads.

Taxis and Ubers have the states NO_PASSENGER and HAS_PASSENGER, and Ubers also have an additional state CALLED. Cars that are in a NO_PASSENGER state, are empty and move around the environment randomly, awaiting a person to want a ride. Cars that are in the state HAS_PASSENGER or CALLED, however, are given a destination and will travel to a destination. Once a person has decided they want a ride, whether it is an Uber or Taxi, he/she will move to their closest pickup point (the lower right corner of the block). If a person has decided to take a cab, that person will wait at a pick up point until an empty cab enters within a radius of four patches from the person. If a person decides to take an uber, that person is assigned an empty uber and awaits the uber at the pickup point. The procedure for Uber and taxi cars to get to their destination is to drive straight if they are not at an intersection (case 1), or choose a random path that takes the agent closer to the desired destination if the car is at an intersection (case 2).
Each tick in the model represents one minute. Every hour, or every 60 ticks, we want to reevaluate the demand and supply to determine whether or not additional Uber cars are necessary. Ubers appear or disappear from the city based on demand.

Passengers are able to call a cab or an Uber, or decide to stay at home, based on the passenger’s ride preferences, to travel to their destination. Passenger agents have preferences for riding an Uber or a cab, as represented by the “Uber-preference” slider. On this Uber preference slider, 1 represents a strong preference for taxi cabs and 10 represents a strong preference for Ubers. There is also a willingness to pay slider, where 1 represents an unlikelihood to pay for high prices and 10 represents a likelihood to be willing to pay for high prices. Passengers prefer Uber if the cost to take an Uber is less than that of taking a taxi. Passengers prefer taxis if the cost to take a taxi is less than that of taking an Uber. The cost to take either an Uber or a taxi exceeds the passenger’s maximum cost tolerance, then the passenger will not want to take any car and “want-car?” will be set to false. Passengers who want to get a ride will move to the closest pickup point and get the closest car.

Passengers also have preferences on the destination that they would like to travel to. The destination preferences are randomized in the model. Every four hours (i.e. 240 ticks), weights will be set up for the various times of day for preferencing for a ride. Weights will be distributed appropriately so that the rides are demanded at hours of the day that reflect real world peak hours. There are two sets of weights that increase and decrease the passenger's decisions that they want a ride, one based on non-freeway weekday traffic distribution and one on non-freeway weekend traffic distribution. For example, ride demand at a time like 4 a.m. will not be very high. Weekday traffic is distinguished from weekend traffic and demand is correlated with simplified real world traffic volume.

Passengers have a cost tolerance variable, which is based on the fare of the transportation method, and determines ride preference. Taxis have their own fare that is set by a slider in the model. Ubers have this baseline fare; however, Uber fares also factor in surge pricing. Surge pricing is a demand-driven scheme that causes Uber fare rates to automatically increase. Every hour (i.e. 60 ticks), the model checks for surge pricing. The surge pricing ratio, a global variable in the model, is calculated by dividing the number of people who want Ubers by the number of available Ubers. The numerator variable (num-people-want-uber) is a count of the passenger agents who have Uber as their ride preference and who are seeking to travel somewhere via Uber. The denominator variable (num-ubers-available) is a count of Ubers on the road who do not have passengers at a given time. If this ratio is greater than 1, then surge pricing is activated. This surge price is multiplied by the Uber fare rate to determine the actual Uber fare that is applied. For example, if there are twice as many of people who want Ubers than the number of Ubers available, then the surge pricing ratio would equal 2.0x. Therefore, the Uber fare would be doubled due to surge pricing.

The main measure of performance for this model is the count of the number of cars on the road. The number of cars on the road is a direct measure of traffic congestion, relative to some baseline number of cars. Specifically, we are interested in the change in the number of total cars and how this correlates to the changes during peak hours, thus showing an increase or decrease in traffic congestion.

##IMPROVEMENTS & EXTENSIONS
One extension would be to include the possibility for passengers to split rides, modeling after services such as Lyft Line or Uber Pool, to further investigate the impact of ridesharing services on traffic congestion. This would entail having passengers who are traveling to the same destination to share the same vehicle. It would be interesting to see how this impacts the number of cars on the road.

Another extension would be to investigate the impact of ridesharing on road safety by building in the potential for car accidents. Car accidents contribute to traffic congestion. One perspective is that due to an increased numbers of cars on the road, and more cars making sudden stops for passenger pickup, ridesharing services make roads less safe. Another perspective claims that services like Uber and Lyft make the roads safer because it decreases the number of drivers who decide to drive after drinking. 21% of respondents used the app to avoid drinking and driving, according to a relevant survey (Bruce, 2014).

Another area of exploration could be to incorporate a more sophisticated algorithm for determining surge pricing for Ubers. This model uses a simplified multiple based on a linear function. One limitation of the model is that the fare of cabs and Ubers do not take distance traveled into account, unlike cabs and Ubers in reality. We chose not to incorporate this aspect when determining the cab fare due to the negligible nature of distance in this simplified city. There are only five locations, so we applied an assumption that the distances from place to place are more or less similar.

Finally, one last suggestion would be to further incorporate real world traffic data by creating a type of car agent that corresponds to privately owned cars. As of now, our model is only concerned with taxi and uber car agents creating traffic congestion. The appearance of private vehicles would impact fare pricing and thus demand, as well as provide people agents an alternative mode of transportation. These cars could be made to appear and disappear proportional to the traffic data, thus making the model more closely resemble the real world.


##SOURCES
Do ridesharing services like Uber and Lyft create traffic jams? (Bruce, 2014)
Ridesharing Can Save Cities from Traffic Congestion (Hower, 2013)
Texas A&M Transportation Institute 2015 Urban Mobility Scorecard and Appendices
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
<experiments>
  <experiment name="experiment" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1441"/>
    <metric>avg-num-cars</metric>
    <metric>max-num-cars</metric>
    <metric>min-num-cars</metric>
    <metric>total-num-cars</metric>
    <enumeratedValueSet variable="num-people">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="uber-preference">
      <value value="3"/>
      <value value="6"/>
      <value value="9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ridesharing-allowed?">
      <value value="true"/>
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-taxis">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cost-tolerance">
      <value value="3"/>
      <value value="6"/>
      <value value="9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-ubers">
      <value value="30"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="is_weekday?">
      <value value="true"/>
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-uber-rate">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="speed-limit">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-taxi-rate">
      <value value="10"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment" repetitions="10" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="1442"/>
    <metric>avg-num-cars</metric>
    <metric>max-num-cars</metric>
    <metric>min-num-cars</metric>
    <metric>total-num-cars</metric>
    <enumeratedValueSet variable="num-people">
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="uber-preference">
      <value value="0"/>
      <value value="2"/>
      <value value="4"/>
      <value value="6"/>
      <value value="8"/>
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="ridesharing-allowed?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-taxis">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-uber-rate">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="cost-tolerance">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="speed-limit">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="num-ubers">
      <value value="30"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="is_weekday?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="base-taxi-rate">
      <value value="10"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
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
