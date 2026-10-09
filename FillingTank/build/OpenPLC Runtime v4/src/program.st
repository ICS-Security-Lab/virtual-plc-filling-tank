PROGRAM main
  VAR
    T_Fill : TON;
    T_Disch : TON;
    Fill_Seq : BOOL;
    Disch_Seq : BOOL;
    Fill_sec : LREAL;
    Left_Calc : LREAL;
    Disch_sec : LREAL;
  END_VAR
  VAR
    Fill_Btn AT %IX0.0 : BOOL;
    Disch_Btn AT %IX0.1 : BOOL;
    Fill_Valve AT %QX0.0 : BOOL;
    Disch_Valve AT %QX0.1 : BOOL;
    Fill_Light AT %QX0.2 : BOOL;
    Timer_Disp AT %QW0 : INT;
    Disch_Light AT %QX0.3 : BOOL;
  END_VAR
  VAR
    _TMP_TIME_TO_S1384184_ENO : BOOL;
    _TMP_TIME_TO_S1384184_OUT : LREAL;
    _TMP_SUB8883323_ENO : BOOL;
    _TMP_SUB8883323_OUT : LREAL;
    _TMP_TO_INT10549693_ENO : BOOL;
    _TMP_TO_INT10549693_OUT : INT;
    _TMP_TIME_TO_S4573589_ENO : BOOL;
    _TMP_TIME_TO_S4573589_OUT : LREAL;
    _TMP_SUB2832327_ENO : BOOL;
    _TMP_SUB2832327_OUT : LREAL;
    _TMP_TO_INT8283863_ENO : BOOL;
    _TMP_TO_INT8283863_OUT : INT;
  END_VAR

  Fill_Seq := NOT(T_Fill.Q) AND NOT(Disch_Seq) AND (Fill_Btn OR Fill_Seq);
  T_Fill(IN := Fill_Seq, PT := T#10s);
  Fill_Valve := Fill_Seq;
  Disch_Seq := NOT(T_Disch.Q) AND NOT(Fill_Seq) AND (Disch_Seq OR NOT(Disch_Btn));
  T_Disch(IN := Disch_Seq, PT := T#10s);
  Disch_Valve := Disch_Seq;
  Fill_Light := Fill_Seq;
  Disch_Light := Disch_Seq;
  _TMP_TIME_TO_S1384184_OUT := TIME_TO_S(EN := Fill_Seq, IN := T_Fill.ET, ENO => _TMP_TIME_TO_S1384184_ENO);
  IF _TMP_TIME_TO_S1384184_ENO THEN
      Fill_sec := _TMP_TIME_TO_S1384184_OUT;
  END_IF;
  _TMP_SUB8883323_OUT := SUB(EN := Fill_Seq, IN1 := 10.0, IN2 := Fill_sec, ENO => _TMP_SUB8883323_ENO);
  IF _TMP_SUB8883323_ENO THEN
      Left_Calc := _TMP_SUB8883323_OUT;
  END_IF;
  _TMP_TO_INT10549693_OUT := TO_INT(EN := Fill_Seq, IN := Left_Calc, ENO => _TMP_TO_INT10549693_ENO);
  IF _TMP_TO_INT10549693_ENO THEN
      Timer_Disp := _TMP_TO_INT10549693_OUT;
  END_IF;
  _TMP_TIME_TO_S4573589_OUT := TIME_TO_S(EN := Disch_Seq, IN := T_Disch.ET, ENO => _TMP_TIME_TO_S4573589_ENO);
  IF _TMP_TIME_TO_S4573589_ENO THEN
      Disch_sec := _TMP_TIME_TO_S4573589_OUT;
  END_IF;
  _TMP_SUB2832327_OUT := SUB(EN := Disch_Seq, IN1 := 10.0, IN2 := Disch_sec, ENO => _TMP_SUB2832327_ENO);
  IF _TMP_SUB2832327_ENO THEN
      Left_Calc := _TMP_SUB2832327_OUT;
  END_IF;
  _TMP_TO_INT8283863_OUT := TO_INT(EN := Disch_Seq, IN := Left_Calc, ENO => _TMP_TO_INT8283863_ENO);
  IF _TMP_TO_INT8283863_ENO THEN
      Timer_Disp := _TMP_TO_INT8283863_OUT;
  END_IF;
END_PROGRAM


CONFIGURATION Config0

  RESOURCE Res0 ON PLC
    TASK task0(INTERVAL := T#100ms,PRIORITY := 1);
    PROGRAM instance0 WITH task0 : main;
  END_RESOURCE
END_CONFIGURATION
