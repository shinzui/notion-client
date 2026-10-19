{-# LANGUAGE GHC2024 #-}
{-# LANGUAGE CPP #-}

module OAuthExamplePlatform (tests) where

#ifndef mingw32_HOST_OS
import OAuthExampleTests qualified
import Test.Tasty (TestTree)
#else
import Test.Tasty (TestTree, testGroup)
#endif

tests :: TestTree
#ifndef mingw32_HOST_OS
tests = OAuthExampleTests.tests
#else
tests = testGroup "OAuthExample (POSIX only)" []
#endif
