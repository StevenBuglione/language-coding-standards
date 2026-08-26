//! Negative fixture: a sprawling, deeply branched function that exceeds the
//! template's complexity ceiling (`clippy.toml`:
//! `too-many-lines-threshold = 30`). Expected trip: clippy::too_many_lines,
//! denied through the workspace lints and enabled explicitly by this probe.
//!
//! Historical note: the original plan pinned `cognitive_complexity`, but
//! that lint no longer emits on current clippy (its documentation disclaims
//! it as a measurement tool); see LANG_SPEC.md for the documented swap.

#[must_use]
pub fn classify(score: u32, alpha: bool, beta: bool, gamma: bool, delta: bool) -> u32 {
    let mut points = score / 10;

    if score > 90 {
        points += 3;
        if !alpha {
            points += 1;
            if delta {
                points *= 2;
            }
        }
    } else if score < 10 {
        points = 0;
    }

    if beta {
        points += 1;
        if gamma {
            for step in 0..score.min(5) {
                match step {
                    0 => {
                        if delta {
                            points += 2;
                        } else {
                            points -= 1;
                        }
                    }
                    1 => {
                        points += 1;
                        if score.is_multiple_of(2) {
                            points *= 2;
                        }
                    }
                    _ => {
                        while points.is_multiple_of(7) && points > 0 {
                            points /= 7;
                        }
                    }
                }
            }
        } else {
            points += score / 100;
        }
    }

    if points == 0 {
        return 0;
    }
    if points < 10 {
        return points * 3;
    }
    if points < 20 {
        return points * 2;
    }
    if points < 30 && !gamma {
        points -= 5;
    }
    if points > 42 {
        points - 7
    } else {
        points + 1
    }
}
