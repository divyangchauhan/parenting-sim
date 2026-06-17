# Content authoring guide

All player-facing text and choices live here, not in code. Writers edit JSON in
`events/`, `interstitials/`, and `endings.json`. The headless validator (PR-02) checks every
file against this schema. **If it's text the player reads, it belongs in `content/`.**

## Event card — `events/<id>.json`
```jsonc
{
  "id": "child_bedtime_story",     // unique, snake_case
  "source": "child",               // child | partner | work | self
  "day_min": 1,                    // earliest day eligible
  "day_max": 7,                    // latest day eligible
  "priority": 5,                   // higher = surfaces earlier in the queue
  "prompt": "\"One more story. Pleeease.\"",
  "conditions": {                  // optional; card only eligible if all pass
    "flags_any": [],               // appears if run has ANY of these flags
    "flags_none": ["child_asleep"],// hidden if run has ANY of these
    "state_min": { "connection": -5 }, // hidden-state floors
    "state_max": {}                    // hidden-state ceilings
  },
  "responses": [
    {
      "text": "Read it. Voices and all.",
      "tone": "warm",                          // warm | neutral | curt
      "cost": { "time": 2, "energy": 2, "patience": 0 },
      "gated_by": { "energy_min": 2, "patience_min": 1 }, // locked below these
      "effects": { "connection": 2, "wellbeing": -1 },    // deltas to hidden states
      "sets_flags": ["child_asleep"],
      "followup": ""               // optional event id to enqueue (deferred consequence)
    },
    {
      "text": "\"It's late. Lights out.\"",
      "tone": "curt",
      "cost": { "time": 1, "energy": 0, "patience": 1 },
      "effects": { "connection": -1, "security": -1 }
    }
  ]
}
```

### Rules the validator enforces
- `id` unique across all events; `source` in the allowed set; `tone` in the allowed set.
- `day_min <= day_max`; both within the configured week length.
- Every `followup` references an existing event `id`.
- 2–3 responses per card. Costs ≥ 0. Effects keys must be known hidden states.
- At least one response must be reachable at zero reserves (no card can fully soft-lock).

## Interstitial — `interstitials/<id>.json`
A quiet beat between days, selected by state.
```jsonc
{
  "id": "dark_hallway",
  "after_day_min": 1,
  "select_when": { "state_min": {}, "state_max": { "wellbeing": -3 } },
  "lines": ["The house is finally quiet.", "You stand in the hallway, listening to them breathe."],
  "art": "hallway_night"          // optional art key
}
```

## Endings — `endings.json`
Array of ending variants, scored against final hidden states; best match wins.
```jsonc
[
  {
    "id": "the_stories",
    "title": "They'll remember the stories.",
    "match": { "state_min": { "connection": 6 } },
    "priority": 10,
    "lines": ["You were tired. You were there anyway.", "..."]
  }
]
```

## Authoring principles (tone)
- No option is "correct." Each trades one good for another.
- Effects are quiet and sometimes delayed (use `followup`). Never moralize in the text.
- Curt/harsh options should feel *earned by exhaustion*, not villainous.
- Write the way the day actually sounds. Less is more. Trust the silence.
