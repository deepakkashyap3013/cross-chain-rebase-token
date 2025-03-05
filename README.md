## Cross chain rebase token

1. A protocol that allows user to deposit into a vault and in return, receive rebase tokens that represents their underlying balance
2. Rebase Token -> balanceOf function is dynamic to show the changing balance with time.
    - Balance increases linearly with time.
    - mint tokens to our users every time they perform an action (minting, burning, transferring, or ... briding)
3. Interest Rate -> 
    - Indivisually sets an interest rate for each user based on some global interest rate of the protocl at the time the user deposits into the vault.
    - This global interest rate can only decrease to incentivize/reward early adopters.
    - Increased token adoption!!
