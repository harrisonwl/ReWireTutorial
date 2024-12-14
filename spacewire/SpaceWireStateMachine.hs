{-# LANGUAGE DataKinds #-}

import ReWire 
import ReWire.Bits 

------------------------------------------------------------
-- Machine states, register file, and input and output types
------------------------------------------------------------

-- | In the original, there are six states, and the
-- | current state is kept in 3-bit register "link_state":
-- |       reg [2:0] link_state;
-- localparam SLSM_ERROR_RESET  = 0;
-- localparam SLSM_ERROR_WAIT   = 1;
-- localparam SLSM_READY        = 2;
-- localparam SLSM_STARTED      = 3;
-- localparam SLSM_CONNECTING   = 4;
-- localparam SLSM_RUN          = 5;

-- | Rather than a 3-bit word (i.e., W 3 in ReWire), just
-- | define the states as a data type with
-- |      link_state :: State
data State = SLSM_ERROR_RESET
           | SLSM_ERROR_WAIT
           | SLSM_READY
           | SLSM_STARTED
           | SLSM_CONNECTING
           | SLSM_RUN

-- | Anything defined with "reg" in Verilog goes here:
data Reg = Reg { rx_en                  :: Bit
               , tx_en                  :: Bit
               , got_null_sync_reg      :: Bit
               , timer_6p4_us_reset     :: Bit
               , timer_12p8_us_start    :: Bit
               , send_fcts              :: Bit
               , send_nulls             :: Bit
               , send_n_char            :: Bit
               , send_time_code         :: Bit
               , stat_info_link_up_en   :: Bit
               , stat_info_link_down_tx :: Bit
               , stat_info_link_up_tx   :: Bit
               , space_wire_reset_n_out :: Bit
               , link_disable_z1        :: Bit
               , rx_error_sync          :: Bit
               , char_sequence_error    :: Bit
               , auto_start_z0          :: Bit
               , auto_start_z1          :: Bit
               , link_start_z0          :: Bit
               , link_start_z1          :: Bit
               , fifo_available_z0      :: Bit
               , fifo_available_z1      :: Bit
--               , link_state           :: W 3
               , link_state             :: State               
               }

data Input = Input { i_clk              :: Bit
                   , i_rx_clk           :: Bit
                   , i_reset_n          :: Bit
                   , i_after_12p8_us    :: Bit
                   , i_after_6p4_us     :: Bit
                   , i_link_start       :: Bit
                   , i_link_disable     :: Bit
                   , i_auto_start       :: Bit
                   , i_got_fct          :: Bit
                   , i_got_time_code    :: Bit
                   , i_got_n_character  :: Bit
                   , i_got_null         :: Bit
                   , i_rx_error         :: Bit
                   , i_credit_error     :: Bit
                   , i_fifo_available   :: Bit
                   , got_null_sync      :: Bit --
                   , got_fct_sync       :: Bit --
                   , got_time_code_sync :: Bit --
                   , got_n_char_sync    :: Bit --
                   }



-- | Output signals collected here:
data Output = Output { o_tx_en                  :: Bit
                     , o_send_nulls             :: Bit
                     , o_send_fcts              :: Bit 
                     , o_send_n_character       :: Bit
                     , o_send_time_codes        :: Bit
                     , o_rx_en                  :: Bit
                     , o_char_sequence_error    :: Bit
                     , o_space_wire_reset_n_out :: Bit
                     , o_timer_6p4_us_reset     :: Bit
                     , o_timer_12p8_us_start    :: Bit
                     , o_stat_info_link_up_tx   :: Bit
                     , o_stat_info_link_down_tx :: Bit
                     , o_stat_info_link_up_en   :: Bit
                     , o_null_sync              :: Bit
                     , o_fct_sync               :: Bit
                     }

------------------------------------------------------------
-- Some convenient shorthand
------------------------------------------------------------

type M   = StateT Reg Identity
type Dev = ReacT Input Output M

-- | Turns an M-action into a single cycle operation
{-# INLINE step #-}
step :: Monad m => StateT s m o -> ReacT i o (StateT s m) i
step x = lift x >>= signal

-- | Reads a register's current value
{-# INLINE reg #-}
reg :: Monad m => (s -> a) -> StateT s m a
reg f = get >>= return . f

-- | "If-then"
{-# INLINE (<?>) #-}
(<?>) :: Monad m => Bit -> StateT s m () -> StateT s m ()
tst <?> x = if tst then x else return ()

{-# INLINE (<??>) #-}
(<??>) :: (Reg -> Bit) -> M () -> M ()
r <??> x = do
             rf <- get
             if r rf then x else return ()

------------------------------------------------------------
-- State machine dispatcher:
--   1. Looks up the link_state "program counter";
--   2. Chooses the corresponding transition; and
--   3. Also, passes along the current external input.
------------------------------------------------------------

dispatch :: Input -> ReacT Input Output M ()
dispatch i = do
                s <- lift (reg link_state)
                case s of
                  SLSM_ERROR_RESET -> step (slsm_error_reset i) >>= dispatch
                  SLSM_ERROR_WAIT  -> step (slsm_error_wait i)  >>= dispatch
                  SLSM_READY       -> step (slsm_ready i)       >>= dispatch
                  SLSM_STARTED     -> step (slsm_started i)     >>= dispatch
                  SLSM_CONNECTING  -> step (slsm_connecting i)  >>= dispatch
                  SLSM_RUN         -> step (slsm_run i)         >>= dispatch

-- | At the end of each cycle, the outputs are computed
-- | and signals them to the output ports.
-- | This function computes the output:
mkoutput :: Input -> M Output
mkoutput i = do
                rf <- get
                return $
                  Output { o_tx_en                  = tx_en rf 
                         , o_send_nulls             = send_nulls rf 
                         , o_send_fcts              = send_fcts rf  
                         , o_send_n_character       = send_n_char rf 
                         , o_send_time_codes        = send_time_code rf 
                         , o_rx_en                  = rx_en rf 
                         , o_char_sequence_error    = char_sequence_error rf
                         , o_space_wire_reset_n_out = space_wire_reset_n_out rf 
                         , o_timer_6p4_us_reset     = timer_6p4_us_reset rf 
                         , o_timer_12p8_us_start    = timer_12p8_us_start rf 
                         , o_stat_info_link_up_tx   = stat_info_link_up_tx rf 
                         , o_stat_info_link_down_tx = stat_info_link_down_tx rf 
                         , o_stat_info_link_up_en   = stat_info_link_up_en rf 
                         , o_null_sync              = got_null_sync i
                         , o_fct_sync               = got_fct_sync i
                         }

-- | 
-- | Compare ^^^^ with this Verilog from space_wire_state_machine.v:
-- |
-- assign o_char_sequence_error           = char_sequence_error;  // Out IP-core
-- assign o_tx_en                         = tx_en;
-- assign o_send_nulls                    = send_nulls;
-- assign o_send_fcts                     = send_fcts;
-- assign o_send_n_character              = send_n_char;
-- assign o_send_time_codes               = send_time_code;
-- assign o_rx_en                         = rx_en;
-- assign o_space_wire_reset_n_out        = space_wire_reset_n_out;
-- assign o_timer_6p4_us_reset            = timer_6p4_us_reset;
-- assign o_timer_12p8_us_start           = timer_12p8_us_start;
-- assign o_stat_info_link_up_tx          = stat_info_link_up_tx;
-- assign o_stat_info_link_down_tx        = stat_info_link_down_tx;
-- assign o_stat_info_link_up_en          = stat_info_link_up_en;
-- assign o_null_sync                     = got_null_sync;
-- assign o_fct_sync                      = got_fct_sync;

------------------------------------------------------------
-- State machine transitions.
------------------------------------------------------------

-- | First three defined below.
slsm_ready , slsm_run , slsm_error_reset
  , slsm_error_wait , slsm_started , slsm_connecting :: Input -> M Output

-- |
-- |
-- |

slsm_error_reset i = do
  modify (\ rf -> rf { stat_info_link_up_en = zero
                     , got_null_sync_reg    = zero })
  rf <- get
  let v = if send_time_code rf then one else zero
  modify (\ rf -> rf { stat_info_link_down_tx = v })
  fifo_available_z1 <??> modify (\ rf -> rf { timer_6p4_us_reset = zero })
  modify (\ rf -> rf { timer_6p4_us_reset = zero
                     , space_wire_reset_n_out = zero
                     , rx_en                  = zero
                     , tx_en                  = zero
                     , send_nulls             = zero
                     , send_fcts              = zero
                     , send_n_char            = zero
                     , send_time_code         = zero
                     , char_sequence_error    = zero })
  rf <- get
  if rx_error_sync rf
    then
      modify (\ rf -> rf { link_state = SLSM_ERROR_RESET })
    else
      i_after_6p4_us i <?> modify (\ rf -> rf { timer_12p8_us_start = one
                                             , link_state           = SLSM_ERROR_WAIT })
  mkoutput i               


-- |
-- |
-- |

slsm_error_wait i = do
  modify (\ rf -> rf { space_wire_reset_n_out = one
                     , timer_12p8_us_start    = zero
                     , rx_en                  = one
                     , tx_en                  = zero })
  got_null_sync i <?> modify (\ rf -> rf { got_null_sync_reg = one })
  rf <- get
  if rx_error_sync rf
    then
      modify (\ rf -> rf { timer_6p4_us_reset = one
                         , link_state         = SLSM_ERROR_RESET})
    else
      if (got_fct_sync i || got_n_char_sync i || got_time_code_sync i)
        then
          modify (\ rf -> rf { char_sequence_error = one
                             , timer_6p4_us_reset  = one
                             , link_state          = SLSM_ERROR_RESET})
        else
          i_after_12p8_us i <?> modify (\ rf -> rf { link_state = SLSM_READY })
        -- may need a default case: link_state = SLSM_ERROR_RESET
  mkoutput i               


-- |
-- |
-- |
slsm_ready i = do
                  modify (\ rf -> rf { rx_en = one
                                     , tx_en = zero })
                  got_null_sync i <?> modify (\ rf -> rf { got_null_sync_reg = one })
                  rf <- get
                  if rx_error_sync rf
                    then
                         modify (\ rf -> rf { timer_6p4_us_reset = one
                                            , link_state         = SLSM_ERROR_RESET })
                  else
                    if got_fct_sync i || got_n_char_sync i || got_time_code_sync i
                      then
                           modify (\ rf ->
                                     rf { char_sequence_error = one
                                        , timer_6p4_us_reset  = one
                                        , link_state          = SLSM_ERROR_RESET })
                  else
                    if auto_start_z1 rf && got_null_sync_reg rf
                      then
                           modify (\ rf ->
                                     rf { timer_12p8_us_start  = one
                                        , link_state          = SLSM_STARTED })
                  else
                    if link_start_z1 rf
                      then
                           modify (\ rf ->
                                     rf { timer_12p8_us_start = one
                                        , link_state          = SLSM_STARTED})
                  else
                           modify (\ rf -> rf { link_state          = SLSM_ERROR_RESET })
                  mkoutput i

-- |
-- |
-- |
slsm_run i  = do
                modify (\ rf ->
                          rf { tx_en                = one
                             , rx_en                = one
                             , send_fcts            = one
                             , send_nulls           = one
                             , send_n_char          = one
                             , send_time_code       = one
                             , stat_info_link_up_en = one })
                s_t_c <- reg send_time_code
                modify (\ rf -> rf { stat_info_link_up_tx = if not s_t_c then one else zero }) 
                l_d_z1 <- reg link_disable_z1
                rx_e_s <- reg rx_error_sync
                (l_d_z1 || rx_e_s) <?> do
                                          modify (\ rf ->
                                                    rf { timer_6p4_us_reset = one
                                                       , link_state = SLSM_ERROR_RESET })
                mkoutput i

-- |
-- |
-- |

slsm_started i  = do
  modify (\ rf -> rf { tx_en               = one
                     , rx_en               = one
                     , send_nulls          = one
                     , timer_12p8_us_start = zero })
  rf <- get
  if rx_error_sync rf || link_disable_z1 rf
    then
      modify (\ rf -> rf { timer_6p4_us_reset = one
                         , link_state = SLSM_ERROR_RESET })
    else
      if got_fct_sync i || got_n_char_sync i || got_time_code_sync i
        then
          modify (\ rf -> rf { char_sequence_error = one
                             , timer_6p4_us_reset  = one
                             , link_state          = SLSM_ERROR_RESET})
        else
          if i_after_12p8_us i
            then
              modify (\ rf -> rf { timer_6p4_us_reset = one
                                 , link_state         = SLSM_ERROR_RESET })
            else
              if got_null_sync i || got_null_sync_reg rf
                then
                  modify (\ rf -> rf { timer_12p8_us_start = one
                                     , link_state          = SLSM_CONNECTING })
                else
                  modify (\ rf -> rf { link_state          = SLSM_ERROR_RESET })

  mkoutput i

-- |
-- | SLSM_CONNECTING:   // #4
-- |

slsm_connecting i = do
  modify (\ rf -> rf { timer_12p8_us_start = zero
                     , tx_en               = one
                     , rx_en               = one
                     , send_fcts           = one
                     , send_nulls          = one })
  rf <- get
  if rx_error_sync rf
    then
      modify (\ rf -> rf { timer_6p4_us_reset = one
                         , link_state         = SLSM_ERROR_RESET })
    else
      if link_disable_z1 rf
        then
          modify (\ rf -> rf { timer_6p4_us_reset = one
                             , link_state         = SLSM_ERROR_RESET })
        else
          if i_after_12p8_us i
            then
              modify (\ rf -> rf { timer_6p4_us_reset = one
                                 , link_state         = SLSM_ERROR_RESET })
            else 
              if got_n_char_sync i || got_time_code_sync i
                then
                  modify (\ rf -> rf { char_sequence_error = one
                                     , timer_6p4_us_reset  = one
                                     , link_state          = SLSM_ERROR_RESET })
                else
                  if got_fct_sync i
                    then
                      modify (\ rf -> rf { link_state = SLSM_RUN })
                    else
                      modify (\ rf -> rf { link_state = SLSM_ERROR_RESET })

  mkoutput i

---------------------------------------------
-- Start 
---------------------------------------------

start :: ReacT Input Output Identity ()
start = extrude (dispatch input0) reg0

-- Input signals are collected here:
input0 = Input { i_clk              = zero
               , i_rx_clk           = zero
               , i_reset_n          = zero
               , i_after_12p8_us    = zero
               , i_after_6p4_us     = zero
               , i_link_start       = zero
               , i_link_disable     = zero
               , i_auto_start       = zero
               , i_got_fct          = zero
               , i_got_time_code    = zero
               , i_got_n_character  = zero
               , i_got_null         = zero
               , i_rx_error         = zero
               , i_credit_error     = zero
               , i_fifo_available   = zero
               , got_null_sync      = zero --
               , got_fct_sync       = zero --
               , got_time_code_sync = zero --
               , got_n_char_sync    = zero --
               }

-- | Initial reg file.
reg0 :: Reg
reg0 = Reg { rx_en                  = zero
           , tx_en                  = zero
           , got_null_sync_reg      = zero
           , timer_6p4_us_reset     = zero
           , timer_12p8_us_start    = zero
           , send_fcts              = zero
           , send_nulls             = zero
           , send_n_char            = zero
           , send_time_code         = zero
           , stat_info_link_up_en   = zero
           , stat_info_link_down_tx = zero
           , stat_info_link_up_tx   = zero
           , space_wire_reset_n_out = zero
           , link_disable_z1        = zero
           , rx_error_sync          = zero
           , char_sequence_error    = zero
           , auto_start_z0          = zero
           , auto_start_z1          = zero
           , link_start_z0          = zero
           , link_start_z1          = zero
           , fifo_available_z0      = zero
           , fifo_available_z1      = zero
           , link_state             = SLSM_ERROR_RESET
           }
