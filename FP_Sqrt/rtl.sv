
module fp_sqrt (
    input  logic        clk,
    input  logic        reset,
    input  logic        in_valid,
    input  logic [31:0] a,
    output logic        out_valid,
    output logic [31:0] result
);

    logic sign;
    logic [7:0] exponent;
    logic [22:0] fraction;

    logic is_zero;
    logic is_inf;
    logic is_nan;
    logic is_negative;
    logic is_subnormal;

    logic [23:0] significand;
    logic signed [9:0] unbiased_exp;

    logic [24:0] adjusted_significand;
    logic signed [9:0] adjusted_exp;

    integer shift_count;
    integer i;

    logic [63:0] radicand;
    logic [127:0] sqrt_data;

    logic [63:0] sqrt_remainder;
    logic [63:0] sqrt_root;

    // 25 bits are required to preserve rounding carry.
    logic [24:0] rounded_significand;

    logic signed [9:0] output_exp;
    logic round_up;

    logic [31:0] calculated_result;

    function automatic logic [127:0] integer_sqrt_fn(
        input logic [63:0] n
    );

        logic [63:0] op;
        logic [63:0] res;
        logic [63:0] bit_value;

        integer k;

        begin
            op = n;
            res = 64'b0;
            bit_value = 64'h4000000000000000;

            for (k = 0; k < 32; k = k + 1) begin
                if (bit_value > op)
                    bit_value = bit_value >> 2;
            end

            for (k = 0; k < 32; k = k + 1) begin
                if (bit_value != 0) begin
                    if (op >= (res + bit_value)) begin
                        op = op - (res + bit_value);
                        res = (res >> 1) + bit_value;
                    end
                    else begin
                        res = res >> 1;
                    end

                    bit_value = bit_value >> 2;
                end
            end

            integer_sqrt_fn = {op, res};
        end

    endfunction

    // Decode and normalize the input.
    always_comb begin

        sign = a[31];
        exponent = a[30:23];
        fraction = a[22:0];

        is_zero = (exponent == 8'd0) &&
                  (fraction == 23'd0);

        is_inf = (exponent == 8'd255) &&
                 (fraction == 23'd0);

        is_nan = (exponent == 8'd255) &&
                 (fraction != 23'd0);

        is_negative = sign && !is_zero;

        is_subnormal = (exponent == 8'd0) &&
                       (fraction != 23'd0);

        significand = 24'b0;
        unbiased_exp = 10'sd0;
        shift_count = 0;
        i=0;

        adjusted_significand = 25'b0;
        adjusted_exp = 10'sd0;

        if (!is_zero && !is_inf && !is_nan) begin

            if (is_subnormal) begin

                significand = {1'b0, fraction};

                for (i = 0; i < 23; i = i + 1) begin
                    if (!significand[23]) begin
                        significand = significand << 1;
                        shift_count = shift_count + 1;
                    end
                end

                unbiased_exp = -10'sd126 - shift_count;

            end
            else begin

                significand = {1'b1, fraction};

                unbiased_exp =
                    $signed({2'b00, exponent}) - 10'sd127;

            end

            // Make the exponent even.
            if (unbiased_exp[0]) begin

                adjusted_significand = {significand, 1'b0};
                adjusted_exp = unbiased_exp - 10'sd1;

            end
            else begin

                adjusted_significand = {1'b0, significand};
                adjusted_exp = unbiased_exp;

            end

        end

    end

    // Integer square-root datapath and rounding.
    always_comb begin

        radicand = 64'b0;

        if (!is_zero && !is_inf && !is_nan &&
            !is_negative) begin

            radicand =
                {39'b0, adjusted_significand} << 31;

        end

        sqrt_data = integer_sqrt_fn(radicand);

        sqrt_remainder = sqrt_data[127:64];
        sqrt_root = sqrt_data[63:0];

        // Retain the 24 significant bits.
        rounded_significand =
            {1'b0, sqrt_root[27:4]};

        output_exp =
            (adjusted_exp >>> 1) + 10'sd127;

        round_up = 1'b0;

        // Round-to-nearest, ties-to-even.
        if (sqrt_root[3:0] > 4'd8) begin
            round_up = 1'b1;
        end
        else if (sqrt_root[3:0] == 4'd8) begin

            if (sqrt_remainder != 0)
                round_up = 1'b1;

            else if (rounded_significand[0])
                round_up = 1'b1;

        end

        if (round_up)
            rounded_significand =
                rounded_significand + 25'd1;

        // If rounding creates 10.000..., renormalize.
        if (rounded_significand == 25'h1000000) begin

            rounded_significand = 25'h0800000;
            output_exp = output_exp + 10'sd1;

        end

        calculated_result = {
            1'b0,
            output_exp[7:0],
            rounded_significand[22:0]
        };

    end

    // Sequential interface.
    always_ff @(posedge clk) begin

        if (reset) begin

            out_valid <= 1'b0;
            result <= 32'b0;

        end
        else begin

            out_valid <= in_valid;

            if (in_valid) begin

                if (is_zero)
                    result <= a;

                else if (is_nan || is_negative)
                    result <= 32'h7FC00000;

                else if (is_inf)
                    result <= 32'h7F800000;

                else
                    result <= calculated_result;

            end

        end

    end

endmodule
