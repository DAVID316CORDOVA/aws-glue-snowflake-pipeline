




    with grouped_expression as (
    select
        
        
    
  


    
regexp_instr(email, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$', 1, 1, 0, '')


 > 0
 as expression


    from PLAYER_ANALYTICS.silver.stg_player_data
    where
        flag_email_invalido = false
    
    

),
validation_errors as (

    select
        *
    from
        grouped_expression
    where
        not(expression = true)

)

select *
from validation_errors




