using Gen
using GenTF
using Test
using PyCall

@pyimport tensorflow as tf

@testset "basic" begin

    init_W = rand(Float32, 2, 3)
    
    W = tf.get_variable("W", dtype=tf.float32, initializer=init_W)
    x = tf.placeholder(tf.float32, shape=(3,), name="x")
    y = tf.squeeze(tf.matmul(W, tf.expand_dims(x, axis=1)), axis=1)
    
    sess = tf.Session()
    foo = TFFunction(sess, [W], [x], y)

    x = rand(Float32, 3)
    (trace, weight) = initialize(foo, (x,))
    @test weight == 0.
    y = get_retval(trace)
    @test isapprox(y, init_W * x)
    y_grad = rand(Float32, 2)

    (x_grad,) = backprop_params(trace, y_grad)
    @test isapprox(x_grad, init_W' * y_grad)

    (W_grad,) = get_grad_vars(foo)
    @test isapprox(sess[:run](W_grad), y_grad * x')
end

@testset "maximum likelihood" begin

    xs = tf.placeholder(tf.float32, shape=(4,), name="xs")
    w = tf.get_variable("w", dtype=tf.float32, initializer=Float32[0., 0.])
    ones = tf.fill([4], tf.constant(1.0, dtype=tf.float32))
    X = tf.stack([xs, ones], axis=1)
    y_means = tf.squeeze(tf.matmul(X, tf.expand_dims(w, axis=1)), axis=1)

    sess = tf.Session()
    tf_func = TFFunction(sess, [w], [xs], y_means)

    @gen function model(xs::Vector{Float64})
        y_means = @addr(tf_func(xs), :tf_func)
        for i=1:length(xs)
            @addr(normal(y_means[i], 1.), "y-$i")
        end
    end

    (w_grad,) = get_grad_vars(tf_func)
    gradient_step = tf.assign_add(w, tf.scalar_mul(tf.constant(0.01, dtype=tf.float32), w_grad))
    update = nothing
    @pywith tf.control_dependencies([gradient_step]) begin
        update = tf.group(tf_func.accum_zero_op)
    end

    xs = Float64[-2, -1, 1, 2]
    ys = -2 * xs .+ 1
    constraints = DynamicAssignment()
    for (i, y) in enumerate(ys)
        constraints["y-$i"] = y
    end
    for iter=1:1000
        (trace, _) = initialize(model, (xs,), constraints)
        backprop_params(trace, nothing)
        sess[:run](update)
    end
    w_val = sess[:run](w)
    @test isapprox(w_val[1], -2., atol=0.001)
    @test isapprox(w_val[2], 1., atol=0.01)
    
end
