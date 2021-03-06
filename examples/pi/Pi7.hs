{-# LANGUAGE TemplateHaskell #-}
module Main where

import Remote

import Data.List
import Data.Array

type Number = Double

data Seq = Seq {k::Int, x::Number, base::Int, q::Array Int Number, tobreak::Bool}

haltonSeq :: Int -> Int -> [Number]
haltonSeq offset thebase = let
                    digits = 64::Int
                    seqSetup :: Seq -> Int -> Number -> (Seq, Number)
                    seqSetup s j _ = 
                                     let dj =  (k s `mod` base s)
                                         news = s {k = (k s - dj) `div` fromIntegral (base s), x = x s + (fromIntegral dj * ((q s) ! (j+1)))}     
                                      in
                                        (news,fromIntegral dj)
                    seqContinue :: Seq -> Int -> Number -> (Seq, Number)
                    seqContinue s j dj = 
                                     if tobreak s
                                        then (s,dj)
                                        else 
                                               let newdj = dj+1
                                                   newx = x s + (q s) ! (j+1)
                                               in
                                               if newdj < fromIntegral (base s)
                                                  then (s {x=newx,tobreak=True},newdj)
                                                  else (s {x = newx - if j==0 then 1 else (q s) ! j},0)

                    initialState base = let q = array (0,digits*2) [(i,v) | i <- [0..digits*2], let v = if i == 0 then 1 else ((q ! ((i)-1))/fromIntegral base)]
                                        in Seq {k=fromIntegral offset,x=0,tobreak=False,base=base,q=q}
                    theseq base = let
                        first :: (Int,[Number],Seq)
                        first = foldl' (\(n,li,s) _ -> let (news,r) = seqSetup s n 0
                                                       in (n+1,r:li,news)) (0,[],initialState base) [0..digits]
                        second :: [Number] -> Seq -> (Int,[Number],Seq)
                        second d s = foldl' (\(n,li,s) dj -> let (news,r) = seqContinue s n dj
                                                             in (n+1,r:li,news)) (0,[],s {tobreak=False}) d
                        in let (_,firstd,firsts) = first
                               therest1 :: [([Number],Seq)]
                               therest1 = iterate (\(d,s) -> let (_,newd,news) = second (reverse d) s in (newd,news)) (firstd,firsts)
                               therest :: [Number]
                               therest = map (\(_,s) -> x s) therest1
                           in therest
                        in (theseq thebase)

haltonPairs :: Int -> [(Number,Number)]
haltonPairs offset = 
  zip (haltonSeq offset 2) (haltonSeq offset 3)

countPairs :: Int -> Int -> (Int,Int)
countPairs offset count = 
  let range = take count (haltonPairs offset)
      numout = length (filter outCircle range)
   in (count-numout,numout)
  where
     outCircle (x,y) = 
          let fx=x-0.5 
              fy=y-0.5
           in fx*fx + fy*fy > 0.25

worker :: Int -> Int -> TaskM (Int,Int)
worker count offset = 
   let (numin,numout) = countPairs offset count 
    in do tlogS "PI" LoInformation ("Finished mapper from offset "++show offset)
          return (numin,numout)

$( remotable ['worker] )

longdiv :: Integer -> Integer -> Integer -> String
longdiv _ 0 _ = "<inf>"
longdiv numer denom places = 
  let attempt = numer `div` denom 
   in if places==0
         then "" 
         else shows attempt (longdiv2 (numer - attempt*denom) denom (places -1))
   where longdiv2 numer denom places | numer `rem` denom == 0 = "0"
                                     | otherwise = longdiv (numer * 10) denom places

initialProcess :: String -> ProcessM ()
initialProcess "WORKER" =
  receiveWait []

initialProcess "MASTER" = 
  let
        interval = 1000000
        numworkers = 5
        numberedworkers = take numworkers [0,interval..]
        clos = map (worker__closure interval) numberedworkers
  in runTask $ 
        do proms <- mapM newPromise clos
           res <- mapM readPromise proms
           let (sumx,sumy) = foldl' (\(a,b) (c,d) -> (a+c,b+d)) (0,0) res
           let (num,den) = estimatePi (fromIntegral sumx) (fromIntegral sumy)
           tsay ("Done: " ++ longdiv (num) (den) 20)
  where 
    estimatePi ni no | ni + no == 0 = (0,0)
                     | otherwise = (4 * ni , ni+no)

initialProcess _ = error "Role must be WORKER or MASTER"

main = remoteInit (Just "config") [Main.__remoteCallMetaData] initialProcess


