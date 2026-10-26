#echo "64,64"
#docker run --rm -it -v $(pwd):/app -m 64m --memory-swap 64m perftest python performance_test_arcfaceresnet100-11-int8.py
#echo "64,128"
#docker run --rm -it -v $(pwd):/app -m 64m --memory-swap 128m perftest python performance_test_arcfaceresnet100-11-int8.py
#echo "128,128"
#docker run --rm -it -v $(pwd):/app -m 128m --memory-swap 128m perftest python performance_test_arcfaceresnet100-11-int8.py
#echo "64,256"
#docker run --rm -it -v $(pwd):/app -m 64m --memory-swap 256m perftest python performance_test_arcfaceresnet100-11-int8.py
#echo "128,256"
#docker run --rm -it -v $(pwd):/app -m 128m --memory-swap 256m perftest python performance_test_arcfaceresnet100-11-int8.py
#echo "256,256"
#docker run --rm -it -v $(pwd):/app -m 256m --memory-swap 256m perftest python performance_test_arcfaceresnet100-11-int8.py
# <- Not started

#echo "64,512"
#docker run --rm -it -v $(pwd):/app -m 64m --memory-swap 512m perftest python performance_test_arcfaceresnet100-11-int8.py
#echo "128,512"
#docker run --rm -it -v $(pwd):/app -m 128m --memory-swap 512m perftest python performance_test_arcfaceresnet100-11-int8.py
#echo "256,512"
#docker run --rm -it -v $(pwd):/app -m 256m --memory-swap 512m perftest python performance_test_arcfaceresnet100-11-int8.py
#echo "512,512"
#docker run --rm -it -v $(pwd):/app -m 512m --memory-swap 512m perftest python performance_test_arcfaceresnet100-11-int8.py
# <- Crash after weights load

#echo "64,1024"
#docker run --rm -it -v $(pwd):/app -m 64m --memory-swap 1024m perftest python performance_test_arcfaceresnet100-11-int8.py
#echo "128,1024"
#docker run --rm -it -v $(pwd):/app -m 128m --memory-swap 1024m perftest python performance_test_arcfaceresnet100-11-int8.py
#echo "256,1024"
#docker run --rm -it -v $(pwd):/app -m 256m --memory-swap 1024m perftest python performance_test_arcfaceresnet100-11-int8.py
#echo "512,1024"
#docker run --rm -it -v $(pwd):/app -m 512m --memory-swap 1024m perftest python performance_test_arcfaceresnet100-11-int8.py
#echo "1024,1024"
#docker run --rm -it -v $(pwd):/app -m 1024m --memory-swap 1024m perftest python performance_test_arcfaceresnet100-11-int8.py
# <- Crash after applied providers

#echo "64,1088"
#docker run --rm -it -v $(pwd):/app -m 64m --memory-swap 1088m perftest python performance_test_arcfaceresnet100-11-int8.py
#echo "128,1088"
#docker run --rm -it -v $(pwd):/app -m 128m --memory-swap 1088m perftest python performance_test_arcfaceresnet100-11-int8.py
#echo "256,1088"
#docker run --rm -it -v $(pwd):/app -m 256m --memory-swap 1088m perftest python performance_test_arcfaceresnet100-11-int8.py
#echo "512,1088"
#docker run --rm -it -v $(pwd):/app -m 512m --memory-swap 1088m perftest python performance_test_arcfaceresnet100-11-int8.py
#echo "1024,1088"
#docker run --rm -it -v $(pwd):/app -m 1024m --memory-swap 1088m perftest python performance_test_arcfaceresnet100-11-int8.py
#echo "1088,1088"
#docker run --rm -it -v $(pwd):/app -m 1088m --memory-swap 1088m perftest python performance_test_arcfaceresnet100-11-int8.py
# <- Works

echo "64,2048"
docker run --rm -it -v $(pwd):/app -m 64m --memory-swap 2048m perftest python performance_test_arcfaceresnet100-11-int8.py
echo "128,2048"
docker run --rm -it -v $(pwd):/app -m 128m --memory-swap 2048m perftest python performance_test_arcfaceresnet100-11-int8.py
echo "256,2048"
docker run --rm -it -v $(pwd):/app -m 256m --memory-swap 2048m perftest python performance_test_arcfaceresnet100-11-int8.py
echo "512,2048"
docker run --rm -it -v $(pwd):/app -m 512m --memory-swap 2048m perftest python performance_test_arcfaceresnet100-11-int8.py
echo "1024,2048"
docker run --rm -it -v $(pwd):/app -m 1024m --memory-swap 2048m perftest python performance_test_arcfaceresnet100-11-int8.py
#echo "1088,2048"
#docker run --rm -it -v $(pwd):/app -m 1088m --memory-swap 2048m perftest python performance_test_arcfaceresnet100-11-int8.py
echo "2048,2048"
docker run --rm -it -v $(pwd):/app -m 2048m --memory-swap 2048m perftest python performance_test_arcfaceresnet100-11-int8.py
# <- Works
