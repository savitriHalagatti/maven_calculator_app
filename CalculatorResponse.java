package com.itdefined.calculator;

import java.util.Date;

public class CalculatorResponse {

    int x;
    int y;
    int result;
    String time;

    public CalculatorResponse(int x, int y, int result) {
        this.x = x;
        this.y = y;
        this.result = result;
        this.time = new Date().toString();
    }

    public int getX() {
        return x;
    }

    public int getY() {
        return y;
    }

    public int getResult() {
        return result;
    }

    public String getTime() {
        return time;
    }
}
