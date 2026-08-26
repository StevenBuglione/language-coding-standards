/**
 * Deliberately misformatted source that the format gate must reject.
 *
 * See bad_examples/README.md for the manifest of expected signals.
 */

export   function badlySpaced( amount:number ){
const totals={ 'units':   amount }
return  totals['units']+1 }
